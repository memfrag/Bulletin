//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// Unread counts per feed, for the sidebar badges.
///
/// One fetch of the unread set, counted in memory, rather than a count query
/// per feed. That is the right shape for a few thousand unread articles and the
/// wrong shape for a few hundred thousand — the search index takes this over
/// when it lands.
struct UnreadCounts: Sendable {

    private var countsByFeedID: [UUID: Int]

    let total: Int

    init(countsByFeedID: [UUID: Int] = [:]) {
        self.countsByFeedID = countsByFeedID
        self.total = countsByFeedID.values.reduce(0, +)
    }

    /// Counts an already-fetched set of unread articles.
    ///
    /// Used with `@Query`, so the badges update themselves as articles are read.
    init(unreadArticles: [Article]) {
        var counts: [UUID: Int] = [:]
        for article in unreadArticles {
            guard let feedID = article.feedID else { continue }
            counts[feedID, default: 0] += 1
        }
        self.init(countsByFeedID: counts)
    }

    @MainActor
    init(context: ModelContext) throws {
        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { $0.status?.isRead == false }
        )
        descriptor.propertiesToFetch = [\.feedID]

        var counts: [UUID: Int] = [:]
        for article in try context.fetch(descriptor) {
            guard let feedID = article.feedID else { continue }
            counts[feedID, default: 0] += 1
        }
        self.init(countsByFeedID: counts)
    }

    subscript(feedID: UUID) -> Int {
        countsByFeedID[feedID] ?? 0
    }

    /// The unread count for a folder, including everything nested beneath it.
    func count(for folder: Folder) -> Int {
        folder.feedsIncludingDescendants.reduce(0) { $0 + self[$1.id] }
    }
}
