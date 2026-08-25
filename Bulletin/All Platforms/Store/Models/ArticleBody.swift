//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// The heavy text of an article, held only on this machine.
///
/// Bodies are the one thing that never leaves the device: they are large, they
/// are re-derivable from the web, and syncing them would turn iCloud into a
/// content mirror. A second device lists the article from its metadata and
/// fetches the body itself when the user opens it.
///
/// Bodies are evicted once they age past the retention window and re-fetched on
/// demand. An old body may 404 by then, in which case the reader offers the
/// live page instead.
///
/// - Note: Lives in the local store, so it cannot hold a relationship to
///   ``Article`` — SwiftData cannot relate across model configurations. It keys
///   by `articleID` instead.
///
@Model
final class ArticleBody {

    var articleID: UUID = UUID()

    /// Which of the four sources produced this text. A single article can have
    /// a cached body per source.
    var sourceRawValue: String = ArticleTextSource.feed.rawValue

    var contentHTML: String = ""

    /// The same content flattened, for the search index.
    var plainText: String = ""

    var extractedAt: Date = Date()

    init(articleID: UUID, source: ArticleTextSource, contentHTML: String, plainText: String) {
        self.articleID = articleID
        self.sourceRawValue = source.rawValue
        self.contentHTML = contentHTML
        self.plainText = plainText
        self.extractedAt = Date()
    }

    var source: ArticleTextSource {
        get { ArticleTextSource(rawValue: sourceRawValue) ?? .feed }
        set { sourceRawValue = newValue.rawValue }
    }
}
