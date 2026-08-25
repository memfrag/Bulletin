//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftData

/// A peek at what is waiting, without opening the app.
///
/// Deliberately small: the top few unread headlines and a way to refresh. A
/// menu bar popover that tried to be a reader would be a worse reader in a
/// smaller window.
struct MenuBarPopup: View {

    @Environment(\.openWindow) private var openWindow

    @Query(
        filter: #Predicate<Article> { $0.status?.isRead == false },
        sort: [SortDescriptor(\Article.publishedAt, order: .reverse)]
    )
    private var unread: [Article]

    /// How many headlines to show.
    private let previewCount = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if unread.isEmpty {
                Text("Nothing unread.", comment: "Menu bar popup empty state")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(unread.prefix(previewCount)) { article in
                    Button {
                        openMainWindow()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(article.displayTitle)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(article.feed?.displayTitle ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                if unread.count > previewCount {
                    Text("and \(unread.count - previewCount) more",
                         comment: "Menu bar popup overflow line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                }
            }

            Divider()
                .padding(.vertical, 6)

            Button {
                openMainWindow()
            } label: {
                Text("Open Bulletin", comment: "Menu bar popup action")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 280)
        .padding(.top, 10)
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // The main window is a `WindowGroup` with no id, so this asks AppKit to
        // front an existing one rather than opening a second.
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
