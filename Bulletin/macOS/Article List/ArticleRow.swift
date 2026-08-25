//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// One article in the list.
///
/// Read state is carried by weight and an unread dot rather than by colour
/// alone, so it survives both themes and does not depend on colour perception.
struct ArticleRow: View {

    @Environment(Library.self) private var library

    let article: Article

    /// How many feeds carried this same story. Zero when it is not a duplicate.
    var alsoInFeedCount: Int = 0

    private var isRead: Bool { article.status?.isRead ?? false }
    private var isStarred: Bool { article.status?.isStarred ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {

            Circle()
                .fill(isRead ? .clear : Color.accentColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(article.displayTitle)
                    .font(.headline)
                    .fontWeight(isRead ? .regular : .semibold)
                    .foregroundStyle(isRead ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let feedTitle = article.feed?.displayTitle {
                        Text(feedTitle)
                            .lineLimit(1)
                        Text(verbatim: "·")
                    }
                    Text(article.sortDate, format: .relative(presentation: .named))
                    if isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    if article.status?.note != nil {
                        Image(systemName: "note.text")
                    }
                    if alsoInFeedCount > 1 {
                        Text("· also in \(alsoInFeedCount - 1) more",
                             comment: "Shown when the same story came from several feeds")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            ArticleActions(article: article)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let state = isRead ? String(localized: "Read") : String(localized: "Unread")
        let feed = article.feed?.displayTitle ?? ""
        return "\(article.displayTitle), \(feed), \(state)"
    }
}

// MARK: - Actions

/// The actions available on an article, shared by the context menu and the
/// Articles menu so the two can never drift apart.
struct ArticleActions: View {

    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL

    let article: Article

    /// How many feeds carried this same story. Zero when it is not a duplicate.
    var alsoInFeedCount: Int = 0

    var body: some View {
        Button {
            library.toggleRead(article)
        } label: {
            (article.status?.isRead ?? false)
                ? Text("Mark as Unread", comment: "Article action")
                : Text("Mark as Read", comment: "Article action")
        }

        Button {
            library.toggleStarred(article)
        } label: {
            (article.status?.isStarred ?? false)
                ? Text("Remove Star", comment: "Article action")
                : Text("Star", comment: "Article action")
        }

        Button {
            library.isPresentingTagEditor = true
        } label: {
            Text("Tags…", comment: "Article action")
        }

        Button {
            library.isPresentingNoteEditor = true
        } label: {
            article.status?.note == nil
                ? Text("Add Note…", comment: "Article action")
                : Text("Edit Note…", comment: "Article action")
        }

        Divider()

        if let url = article.url {
            Button {
                openURL(url)
            } label: {
                Text("Open in Browser", comment: "Article action")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            } label: {
                Text("Copy Link", comment: "Article action")
            }
        }
    }
}
