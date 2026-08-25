//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// What the reader column should be showing.
enum ReaderContent: Equatable {

    case empty

    /// Fetching the page. Only ever shown for a genuine fetch — a body already
    /// extracted goes straight to `.html`, so revisiting an article never
    /// flashes a spinner.
    case loading(source: ArticleTextSource)

    /// Article markup, ready to be wrapped in the reader's own document.
    case html(String, source: ArticleTextSource)

    /// Extraction failed, so this is the feed's own text plus a note saying so.
    ///
    /// A truncated summary is still something to read; an error page is not.
    case failedWithFallback(message: String, fallbackHTML: String, source: ArticleTextSource)

    case failed(String, source: ArticleTextSource)

    /// The live page, rendered as itself.
    case liveWebPage(URL)
}

extension ReaderContent {

    var source: ArticleTextSource? {
        switch self {
        case .empty: nil
        case .loading(let source): source
        case .html(_, let source): source
        case .failedWithFallback(_, _, let source): source
        case .failed(_, let source): source
        case .liveWebPage: .liveWebPage
        }
    }
}
