//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// What the app cannot explain by being looked at.
///
/// Mostly the query language. A stream is a saved query, the query has a text
/// form, and a text form nobody can discover is a text form nobody uses — so
/// the grammar is written down where the Help menu points.
struct HelpView: View {

    private enum Topic: Hashable {
        case queries
        case keyboard
        case textSources
    }

    @State private var topic: Topic = .queries

    var body: some View {
        NavigationSplitView {
            List(selection: $topic) {
                NavigationLink(value: Topic.queries) {
                    Label("Streams & Searching", systemImage: "line.3.horizontal.decrease.circle")
                }
                NavigationLink(value: Topic.keyboard) {
                    Label("Keyboard", systemImage: "keyboard")
                }
                NavigationLink(value: Topic.textSources) {
                    Label("Article Text", systemImage: "doc.plaintext")
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 200)
        } detail: {
            ScrollView {
                Group {
                    switch topic {
                    case .queries: QueryHelp()
                    case .keyboard: KeyboardHelp()
                    case .textSources: TextSourceHelp()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

// MARK: - Queries

private struct QueryHelp: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HelpHeading("Streams & Searching")

            HelpParagraph("""
                A stream is a saved search. It is evaluated fresh every time you look at it, so it is \
                always current and nothing is ever filed, moved or changed to make it match.
                """)

            HelpParagraph("""
                You can build a stream from the rows in the editor, or type the query directly — they \
                are two views of the same thing, and editing either updates the other.
                """)

            HelpCode("unread folder:Dev -tag:noise title:swift after:7d")

            HelpParagraph("""
                Typing in the search field uses the same language. Searching while a stream is \
                selected narrows that stream rather than replacing it.
                """)

            HelpSubheading("Conditions")

            HelpTable(rows: [
                ("unread", "Not yet read"),
                ("read", "Already read"),
                ("starred", "Starred"),
                ("unstarred", "Not starred"),
                ("annotated", "Has a note")
            ])

            HelpSubheading("Fields")

            HelpTable(rows: [
                ("title:swift", "Title contains “swift”"),
                ("author:gruber", "Author contains “gruber”"),
                ("feed:fireball", "From a feed whose name contains “fireball”"),
                ("folder:Dev", "In the Dev folder, or any folder inside it"),
                ("tag:ios", "Tagged exactly “ios”"),
                ("url:example.com", "Link contains “example.com”")
            ])

            HelpSubheading("Dates")

            HelpTable(rows: [
                ("after:7d", "Published in the last seven days"),
                ("before:30d", "Older than thirty days"),
                ("after:2026-01-01", "On or after a specific date")
            ])

            HelpParagraph("""
                Relative dates stay relative: a stream saying after:7d still means the last week next \
                month.
                """)

            HelpSubheading("Combining")

            HelpTable(rows: [
                ("unread starred", "Both — conditions side by side mean “and”"),
                ("unread OR starred", "Either"),
                ("-tag:noise", "Not — a leading minus negates"),
                ("(unread OR starred) title:swift", "Parentheses group"),
                ("\"exact phrase\"", "Quoted text is searched as written")
            ])

            HelpParagraph("""
                Words on their own search the article’s title and text. Quoting matters: unread is the \
                condition, while "unread" searches for the word.
                """)
        }
    }
}

// MARK: - Keyboard

private struct KeyboardHelp: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HelpHeading("Keyboard")

            HelpParagraph("""
                Everything here is also in a menu. Arrow keys move within a column and Tab moves \
                between them.
                """)

            HelpSubheading("In the article list")

            HelpTable(rows: [
                ("↑ ↓", "Move through articles"),
                ("Tab / ⇧Tab", "Move between the three columns"),
                ("Return", "Open in your browser"),
                ("S", "Star or unstar"),
                ("U", "Mark read or unread"),
                ("T", "Tags"),
                ("N", "Note"),
                ("R", "Refresh all feeds")
            ])

            HelpSubheading("Anywhere")

            HelpTable(rows: [
                ("⌘N", "Subscribe to a feed"),
                ("⌘R", "Refresh all feeds"),
                ("⇧⌘K", "Mark everything in this stream read"),
                ("⇧⌘S", "Save the current search as a stream"),
                ("⇧⌘T", "Switch where the article text comes from"),
                ("⇧⌘I", "Import subscriptions from an OPML file"),
                ("⇧⌘E", "Export subscriptions")
            ])

            HelpParagraph("""
                Selecting an article marks it read after about a second, so moving quickly past one \
                does not mark it. Articles you read stay in the list until you leave the stream and \
                come back.
                """)

            HelpSubheading("Refreshing")

            HelpParagraph("""
                Bulletin never polls in the background. Feeds are fetched when you launch it, when \
                you come back to it after the interval set in Settings, and whenever you ask. A feed \
                that keeps failing is retried less often; \u{2318}R always tries it anyway.
                """)
        }
    }
}

// MARK: - Text sources

private struct TextSourceHelp: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HelpHeading("Article Text")

            HelpParagraph("""
                Many feeds send only the first paragraph. Bulletin can fetch the rest, and the toolbar \
                control chooses how.
                """)

            HelpTable(rows: [
                ("Feed Text", "Whatever the feed itself sent"),
                ("Extracted", "Fetches the page and pulls the article out of it"),
                ("Extracted (Readability)", "Loads the page fully — slower, but wins on awkward sites"),
                ("Web Page", "The real page, for paywalls and interactive articles")
            ])

            HelpParagraph("""
                Changing this while reading sets the default for that whole feed, so a feed that always \
                truncates only needs fixing once. To change it for a single article, use Only This \
                Article in the same menu.
                """)

            HelpParagraph("""
                Article text is fetched when you open an article, never in the background, and is kept \
                for a while afterwards so it is there if you come back. How long is up to you in \
                Settings; titles, dates and links are always kept regardless, so searching still finds \
                everything.
                """)
        }
    }
}

// MARK: - Pieces

private struct HelpHeading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.title2).fontWeight(.semibold)
    }
}

private struct HelpSubheading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).padding(.top, 6)
    }
}

private struct HelpParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
    }
}

private struct HelpCode: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A two-column reference: the thing you type, and what it does.
private struct HelpTable: View {

    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Text(row.1)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    HelpView()
}
