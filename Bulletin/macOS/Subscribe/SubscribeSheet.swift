//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import FeedIngest

/// Adds a feed from whatever URL the user has.
///
/// It takes a site's homepage, not just a feed URL, because nobody keeps feed
/// URLs around — they have the address of the site they were just reading.
struct SubscribeSheet: View {

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var searchState: SearchState = .idle
    @State private var selectedFeedURLs: Set<URL> = []

    private enum SearchState: Equatable {
        case idle
        case searching
        case found([DiscoveredFeed])
        case nothingFound
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Add Feed", comment: "Subscribe sheet title")
                .font(.headline)

            HStack {
                TextField(
                    text: $urlText,
                    prompt: Text(verbatim: "https://example.com")
                ) {
                    Text("Site or feed address", comment: "Subscribe sheet field label")
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(search)

                Button(action: search) {
                    Text("Find Feeds", comment: "Discover feeds at a URL")
                }
                .disabled(normalizedURL == nil || searchState == .searching)
            }

            resultsView

            Spacer(minLength: 0)

            HStack {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Cancel", comment: "Dismiss the sheet")
                }

                Spacer()

                Button(action: subscribe) {
                    Text("Subscribe", comment: "Confirm subscribing to the selected feeds")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFeedURLs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 340)
        .onAppear {
            // A URL that arrived from Safari or a bulletin:// link starts the
            // search straight away — the user already said what they wanted.
            if let incoming = SubscriptionInbox.shared.take() {
                urlText = incoming.absoluteString
                search()
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsView: some View {
        switch searchState {
        case .idle:
            ContentUnavailableView {
                Label("Paste an Address", systemImage: "link")
            } description: {
                Text("A site's home page works — Bulletin will find its feeds.",
                     comment: "Subscribe sheet idle state")
            }

        case .searching:
            VStack {
                ProgressView()
                Text("Looking for feeds…", comment: "Subscribe sheet searching state")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .found(let feeds):
            List(feeds, id: \.url) { feed in
                Toggle(isOn: binding(for: feed)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feed.title ?? feed.url.lastPathComponent)
                        Text(feed.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .listStyle(.bordered)

        case .nothingFound:
            ContentUnavailableView {
                Label("No Feeds Found", systemImage: "questionmark.circle")
            } description: {
                Text("That page does not advertise a feed. Try the feed's own address.",
                     comment: "Subscribe sheet no-results state")
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Could Not Reach That Address", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
    }

    private func binding(for feed: DiscoveredFeed) -> Binding<Bool> {
        Binding(
            get: { selectedFeedURLs.contains(feed.url) },
            set: { isOn in
                if isOn {
                    selectedFeedURLs.insert(feed.url)
                } else {
                    selectedFeedURLs.remove(feed.url)
                }
            }
        )
    }

    // MARK: - Actions

    /// Accepts a bare host by assuming https, because that is what people paste.
    private var normalizedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func search() {
        guard let url = normalizedURL else { return }
        searchState = .searching
        selectedFeedURLs = []

        Task {
            do {
                let feeds = try await library.discoverFeeds(at: url)
                if feeds.isEmpty {
                    searchState = .nothingFound
                } else {
                    searchState = .found(feeds)
                    // Pre-select the first, which is the main feed on nearly
                    // every site that offers more than one.
                    if let first = feeds.first {
                        selectedFeedURLs = [first.url]
                    }
                }
            } catch {
                searchState = .failed(error.localizedDescription)
            }
        }
    }

    private func subscribe() {
        guard case .found(let feeds) = searchState else { return }

        for feed in feeds where selectedFeedURLs.contains(feed.url) {
            try? library.subscribe(to: feed.url, title: feed.title ?? "")
        }
        dismiss()

        Task { await library.refreshAll() }
    }
}
