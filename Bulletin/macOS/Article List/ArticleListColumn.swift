//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftData

/// The middle column: the articles matching the selected sidebar item.
struct ArticleListColumn: View {

    @Environment(Library.self) private var library

    let item: SidebarItem?

    var body: some View {
        // Re-created whenever the selection or the query result changes, because
        // a `@Query` takes its descriptor at initialization.
        ArticleList(
            item: item,
            feedIDs: library.feedIDs(for: item),
            retainedArticleIDs: library.retainedArticleIDs,
            matchedArticleIDs: library.matchedArticleIDs,
            duplicateGroups: library.duplicateGroups
        )
        .id(item)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }

    private var title: String {
        switch item {
        case .builtInStream(let stream):
            stream.title
        case .stream(let id):
            library.stream(withID: id)?.name ?? String(localized: "Stream")
        case .feed(let id):
            library.feed(withID: id)?.displayTitle ?? String(localized: "Feed")
        case .folder(let id):
            library.folder(withID: id)?.name ?? String(localized: "Folder")
        case .none:
            String(localized: "Articles")
        }
    }

    private var subtitle: String {
        library.lastRefresh?.statusText ?? ""
    }
}

// MARK: - Article List

private struct ArticleList: View {

    @Environment(Library.self) private var library

    @Query private var articles: [Article]

    private let item: SidebarItem?
    private let duplicateGroups: [String: [UUID]]

    init(
        item: SidebarItem?,
        feedIDs: [UUID],
        retainedArticleIDs: [UUID],
        matchedArticleIDs: [UUID]?,
        duplicateGroups: [String: [UUID]]
    ) {
        self.item = item
        self.duplicateGroups = duplicateGroups
        _articles = Query(
            ArticleQuery.descriptor(
                for: item,
                feedIDs: feedIDs,
                retainedArticleIDs: retainedArticleIDs,
                matchedArticleIDs: matchedArticleIDs
            )
        )
    }

    /// The same story from several feeds collapses to one row.
    ///
    /// Non-destructive, as everything here is: the duplicates are hidden from
    /// the list, not merged or deleted, and the surviving row says how many
    /// there were.
    private var collapsed: (visible: [Article], alsoIn: [UUID: Int]) {
        guard !duplicateGroups.isEmpty else { return (articles, [:]) }

        var hidden: Set<UUID> = []
        var alsoIn: [UUID: Int] = [:]

        for ids in duplicateGroups.values {
            // The list is newest-first, so the first surviving id is the one
            // the user would have seen anyway.
            guard let keeper = ids.first else { continue }
            alsoIn[keeper] = ids.count
            hidden.formUnion(ids.dropFirst())
        }

        return (articles.filter { !hidden.contains($0.id) }, alsoIn)
    }

    var body: some View {
        @Bindable var library = library
        let (visible, alsoIn) = collapsed

        Group {
            if visible.isEmpty {
                emptyState
            } else {
                List(selection: $library.selectedArticleID) {
                    ForEach(visible) { article in
                        ArticleRow(article: article, alsoInFeedCount: alsoIn[article.id] ?? 0)
                            .tag(article.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .articleKeyboardActions(for: visible)
        .onChange(of: visible.map(\.id), initial: true) { _, ids in
            // The list already has the order; recomputing it in the model just
            // to find "the next three" would mean a second fetch per selection.
            library.visibleArticleIDs = ids
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !library.searchText.isEmpty {
            ContentUnavailableView.search(text: library.searchText)
        } else {
            switch item {
            case .builtInStream(.unread):
                ContentUnavailableView {
                    Label("All Caught Up", systemImage: "checkmark.circle")
                } description: {
                    Text("Nothing left unread.", comment: "Unread stream empty state")
                }
            case .builtInStream(.bookmarked):
                ContentUnavailableView {
                    Label("Nothing Bookmarked", systemImage: "bookmark")
                } description: {
                    Text("Bookmark an article to keep it here.", comment: "Bookmarked stream empty state")
                }
            case .stream:
                ContentUnavailableView {
                    Label("Nothing Matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No articles match this stream's query yet.", comment: "Saved stream empty state")
                }
            default:
                ContentUnavailableView {
                    Label("No Articles", systemImage: "tray")
                } description: {
                    Text("Refresh to fetch the latest.", comment: "Article list empty state")
                }
            }
        }
    }
}
