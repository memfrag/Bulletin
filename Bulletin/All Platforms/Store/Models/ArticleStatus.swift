//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// Everything the user did to an article.
///
/// Kept separate from ``Article`` because it is what changes constantly while
/// reading — metadata is written once at ingest and then left alone.
///
/// - Important: Mirrored to CloudKit — see the note on ``Feed``.
///
@Model
final class ArticleStatus {

    var id: UUID = UUID()

    var article: Article?

    var isRead: Bool = false

    var readAt: Date?

    /// - Note: `originalName` because this was called `isStarred` before
    ///   bookmarking was renamed. Without it SwiftData would treat this as a
    ///   new attribute and every existing bookmark would quietly vanish.
    @Attribute(originalName: "isStarred")
    var isBookmarked: Bool = false

    @Attribute(originalName: "starredAt")
    var bookmarkedAt: Date?

    /// A free-text note on the whole article.
    ///
    /// Deliberately not anchored to a text range: article bodies are pruned and
    /// re-fetched, so any offset-based anchor would rot.
    var note: String?

    @Relationship(inverse: \Tag.statuses)
    var tags: [Tag]? = []

    /// A per-article override of the feed's default text source. `nil` means
    /// follow the feed.
    var textSourceOverrideRawValue: String?

    init(article: Article?) {
        self.id = UUID()
        self.article = article
    }
}

// MARK: - Convenience

extension ArticleStatus {

    var textSourceOverride: ArticleTextSource? {
        get { textSourceOverrideRawValue.flatMap(ArticleTextSource.init(rawValue:)) }
        set { textSourceOverrideRawValue = newValue?.rawValue }
    }

    /// The source this article should actually open with.
    var effectiveTextSource: ArticleTextSource {
        textSourceOverride ?? article?.feed?.textSource ?? .feed
    }
}
