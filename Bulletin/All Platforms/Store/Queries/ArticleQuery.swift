//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// Turns a sidebar selection into a fetch.
///
/// This is the narrow, hand-written version of what the query engine will do
/// generally: the built-in streams and the subscription tree, and nothing else.
/// User-authored queries need a predicate built at runtime, which `#Predicate`
/// cannot express, so they arrive with the search index rather than here.
enum ArticleQuery {

    /// Articles matching a sidebar selection, newest first.
    ///
    /// - Parameter retainedArticleIDs: Articles that have stopped matching since
    ///   the user arrived, but should stay on screen anyway. Without this, an
    ///   article marked read while you are reading it disappears out from under
    ///   the selection and arrowing down the Unread stream lands somewhere
    ///   unpredictable.
    static func descriptor(
        for item: SidebarItem?,
        feedIDs: [UUID] = [],
        retainedArticleIDs: [UUID] = [],
        matchedArticleIDs: [UUID]? = nil
    ) -> FetchDescriptor<Article> {

        // A search or a saved stream is answered by the index, which returns
        // ids; SwiftData's only job then is to load them.
        if let matchedArticleIDs {
            let ids = matchedArticleIDs + retainedArticleIDs
            var descriptor = FetchDescriptor<Article>(
                predicate: #Predicate { ids.contains($0.id) }
            )
            descriptor.sortBy = [
                SortDescriptor(\.publishedAt, order: .reverse),
                SortDescriptor(\.ingestedAt, order: .reverse)
            ]
            return descriptor
        }

        var descriptor = FetchDescriptor<Article>(
            predicate: predicate(for: item, feedIDs: feedIDs, retainedArticleIDs: retainedArticleIDs)
        )

        // Feeds lie about publication dates often enough that ingest time has to
        // be the tie-breaker, but sorting on a computed property is not
        // available to the store, so this sorts on what it can.
        descriptor.sortBy = [
            SortDescriptor(\.publishedAt, order: .reverse),
            SortDescriptor(\.ingestedAt, order: .reverse)
        ]
        return descriptor
    }

    static func predicate(
        for item: SidebarItem?,
        feedIDs: [UUID] = [],
        retainedArticleIDs: [UUID] = []
    ) -> Predicate<Article>? {

        let retained = retainedArticleIDs

        switch item {
        case .builtInStream(.unread):
            return #Predicate { article in
                article.status?.isRead == false || retained.contains(article.id)
            }

        case .builtInStream(.starred):
            return #Predicate { article in
                article.status?.isStarred == true || retained.contains(article.id)
            }

        case .builtInStream(.today):
            let startOfDay = Calendar.current.startOfDay(for: Date())
            return #Predicate { article in
                if let publishedAt = article.publishedAt {
                    return publishedAt >= startOfDay
                } else {
                    return article.ingestedAt >= startOfDay
                }
            }

        case .feed, .folder:
            // Folders match their descendants, so the caller resolves the tree
            // to a flat set of feed ids and passes it in.
            let ids = feedIDs
            return #Predicate { article in
                if let feedID = article.feedID {
                    return ids.contains(feedID)
                } else {
                    return false
                }
            }

        case .stream:
            // Saved queries arrive with the query engine.
            return nil

        case .none:
            return nil
        }
    }
}
