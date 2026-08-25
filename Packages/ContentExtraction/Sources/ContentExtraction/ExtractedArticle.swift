//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The article found on a page.
public struct ExtractedArticle: Sendable, Equatable {

    /// The article's own title, which is often better than the feed's version.
    public let title: String?

    public let byline: String?

    /// The article markup, with the page's chrome removed and relative links
    /// resolved against the page they came from.
    public let contentHTML: String

    /// The same content flattened, for the search index and for judging whether
    /// extraction actually found anything.
    public let plainText: String

    public init(title: String?, byline: String?, contentHTML: String, plainText: String) {
        self.title = title
        self.byline = byline
        self.contentHTML = contentHTML
        self.plainText = plainText
    }
}

// MARK: - Quality

extension ExtractedArticle {

    /// Below this, whatever was extracted is not an article.
    ///
    /// A page that yields two sentences has almost always had its real content
    /// missed — a cookie banner, a paywall stub, a redirect notice. Falling back
    /// is better than showing the user a fragment and calling it the article.
    static let minimumUsefulLength = 200

    /// Whether this looks like a real article rather than a scrap.
    public var isSubstantial: Bool {
        plainText.count >= Self.minimumUsefulLength
    }
}

// MARK: - Errors

public enum ContentExtractionError: Error, Equatable, Sendable {

    /// The page loaded but nothing on it looked like an article.
    case noArticleFound

    case fetchFailed(String)

    case javaScriptFailed(String)

    /// The page took too long. Some pages never stop loading.
    case timedOut
}

extension ContentExtractionError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .noArticleFound:
            String(localized: "No article could be found on that page.")
        case .fetchFailed(let detail):
            String(localized: "The page could not be loaded: \(detail)")
        case .javaScriptFailed(let detail):
            String(localized: "The page could not be processed: \(detail)")
        case .timedOut:
            String(localized: "The page took too long to load.")
        }
    }
}
