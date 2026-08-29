//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The app's own menu commands.
///
/// Every action reachable from the keyboard also lives here, so nothing is
/// discoverable only by already knowing it exists. The commands act on the
/// focused window's reading session.
struct BulletinCommands: Commands {

    @FocusedValue(\.library) private var library

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {

        CommandGroup(replacing: .newItem) {
            Button {
                library?.isPresentingSubscribeSheet = true
            } label: {
                Text("Subscribe…", comment: "Add a new feed subscription")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(library == nil)
        }

        CommandGroup(replacing: .importExport) {
            Button {
                library?.isPresentingOPMLImporter = true
            } label: {
                Text("Import Subscriptions…", comment: "Import an OPML file")
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(library == nil)

            Button {
                library?.isPresentingOPMLExporter = true
            } label: {
                Text("Export Subscriptions…", comment: "Export an OPML file")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(library == nil)
        }

        CommandMenu(Text("Articles", comment: "Menu of article and refresh actions")) {

            Button {
                guard let library else { return }
                // Asking explicitly overrides a failing feed's backoff window.
                Task { await library.refreshAll(force: true) }
            } label: {
                Text("Refresh All Feeds", comment: "Fetch every subscribed feed now")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(library == nil || library?.isRefreshing == true)

            Button {
                openWindow(id: FeedHealthWindow.windowID)
            } label: {
                Text("Feed Health…", comment: "Opens the feed health window")
            }

            Button {
                // A new stream starts from whatever is in the search field,
                // which is how most of them will begin.
                library?.editingStream = nil
                library?.isPresentingStreamEditor = true
            } label: {
                Text("Save Search as Stream…", comment: "Create a saved stream")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(library == nil)

            Divider()

            Button {
                library?.markAllRead(in: library?.selectedItem)
            } label: {
                Text("Mark All as Read", comment: "Mark every article in the current stream read")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(library == nil)

            Divider()

            if let library, let article = library.selectedArticle {
                ArticleActions(article: article)
                    .environment(library)

                Divider()

                // The same control as the reader toolbar. A text source you can
                // only reach by finding an unlabelled toolbar icon is one most
                // people never find.
                Menu {
                    ForEach(ArticleTextSource.allCases) { source in
                        Button {
                            library.setTextSource(source, for: article, scope: .feed)
                        } label: {
                            Label(source.title, systemImage: source.systemImage)
                        }
                    }
                } label: {
                    Text("Text Source", comment: "Menu of article text sources")
                }

                Button {
                    library.cycleTextSource(for: article)
                } label: {
                    Text("Next Text Source", comment: "Cycle to the next article text source")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            } else {
                Button {} label: {
                    Text("Bookmark", comment: "Article action")
                }
                .disabled(true)
            }
        }
    }
}
