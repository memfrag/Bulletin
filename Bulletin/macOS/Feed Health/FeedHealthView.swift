//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftData

struct FeedHealthView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Feed.title) private var feeds: [Feed]

    /// Failing feeds first, then stale-by-silence, then the healthy ones.
    private var ordered: [Feed] {
        feeds.sorted { lhs, rhs in
            if lhs.consecutiveFailureCount != rhs.consecutiveFailureCount {
                return lhs.consecutiveFailureCount > rhs.consecutiveFailureCount
            }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if feeds.isEmpty {
                ContentUnavailableView {
                    Label("No Subscriptions", systemImage: "tray")
                } description: {
                    Text("Nothing to report yet.", comment: "Feed health empty state")
                }
            } else {
                Table(ordered) {
                    TableColumn(Text("Feed", comment: "Feed health column")) { feed in
                        HStack(spacing: 6) {
                            statusIcon(for: feed)
                            Text(feed.displayTitle)
                                .lineLimit(1)
                        }
                    }
                    // The name is what you scan for, so it gets the room. Most
                    // feeds are healthy and their Problem cell is a dash.
                    .width(min: 160, ideal: 240)

                    TableColumn(Text("Last Checked", comment: "Feed health column")) { feed in
                        if let lastFetchedAt = feed.lastFetchedAt {
                            Text(lastFetchedAt, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never", comment: "Feed has never been fetched")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn(Text("Problem", comment: "Feed health column")) { feed in
                        if let message = feed.lastFailureMessage {
                            Text(message)
                                .foregroundStyle(feed.isStale ? .primary : .secondary)
                                .lineLimit(2)
                                .help(message)
                        } else {
                            Text(verbatim: "—")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 120, ideal: 180)
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for feed: Feed) -> some View {
        if feed.isStale {
            // Past the threshold, this is a problem worth acting on.
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(Text("Failing repeatedly", comment: "Feed status"))
        } else if feed.consecutiveFailureCount > 0 {
            // One bad day is not news. It is shown, but quietly.
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
                .help(Text("Failed last time", comment: "Feed status"))
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .help(Text("Healthy", comment: "Feed status"))
        }
    }
}

// Previews use the mock environment, which only exists in DEBUG builds.
#if DEBUG
#Preview {
    FeedHealthView()
        .previewEnvironment()
}
#endif
