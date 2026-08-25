//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// An article's metadata.
///
/// Metadata is never pruned, so search and streams stay complete over the whole
/// history. The body lives in the local store and is evicted on a schedule; see
/// ``ArticleBody``.
///
/// - Important: Mirrored to CloudKit — see the note on ``Feed``. In particular
///   there is no unique constraint on `guid`; ingest dedups on
///   `(feed.id, guid)` in code.
///
@Model
final class Article {

    var id: UUID = UUID()

    /// The feed's own identifier for this item, from `<guid>`, `<id>`, or the
    /// item URL as a last resort. Unique only within a feed.
    var guid: String = ""

    var feed: Feed?

    /// The owning feed's id, denormalized.
    ///
    /// Kept alongside the relationship because `#Predicate` handles a plain
    /// stored property far more reliably than it handles traversing an optional
    /// to-one relationship, and because it is a facet the search index needs
    /// anyway. Written at ingest and never changed.
    var feedID: UUID?

    var title: String = ""

    var author: String?

    /// The article's own URL.
    var url: URL?

    /// The URL after redirects are unwrapped and tracking parameters stripped.
    ///
    /// Two articles sharing this are the same story carried by different feeds,
    /// which is how the list collapses duplicates without mutating anything.
    var canonicalURL: URL?

    /// The feed's own summary or content, kept because it is small and is the
    /// fallback whenever extraction fails.
    var summary: String?

    var publishedAt: Date?

    var ingestedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ArticleStatus.article)
    var status: ArticleStatus?

    init(guid: String, feed: Feed?, title: String = "") {
        self.id = UUID()
        self.guid = guid
        self.feed = feed
        self.feedID = feed?.id
        self.title = title
        self.ingestedAt = Date()
    }
}

// MARK: - Convenience

extension Article {

    /// The date to sort and group by. Feeds lie about publication dates often
    /// enough that ingest time is a necessary fallback.
    var sortDate: Date {
        publishedAt ?? ingestedAt
    }

    var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled") : title
    }
}
