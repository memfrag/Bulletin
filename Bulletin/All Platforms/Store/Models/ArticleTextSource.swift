//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Where the text of an article comes from.
///
/// The reader's toolbar cycles these in order. Changing the source while
/// reading sets the *feed's* default going forward, so a chronically truncated
/// feed only has to be fixed once.
///
enum ArticleTextSource: String, CaseIterable, Sendable {

    /// Whatever the feed itself provided. Often truncated.
    case feed

    /// Fetched with `URLSession` and run through the heuristic Swift extractor.
    /// The default escalation from a truncated feed, and cheap.
    case nativeExtraction

    /// Fetched in a headless `WKWebView` and run through Mozilla's
    /// `readability.js`. Handles pages the heuristic extractor loses against.
    case readabilityExtraction

    /// The live page in a `WKWebView`, unextracted. The escape hatch for
    /// paywalls, interactive pieces, and anything both extractors mangle.
    case liveWebPage
}

// MARK: - Convenience

extension ArticleTextSource: Identifiable {
    var id: Self { self }
}

extension ArticleTextSource {

    var title: String {
        switch self {
        case .feed: String(localized: "Feed Text")
        case .nativeExtraction: String(localized: "Extracted")
        case .readabilityExtraction: String(localized: "Extracted (Readability)")
        case .liveWebPage: String(localized: "Web Page")
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "text.alignleft"
        case .nativeExtraction: "doc.plaintext"
        case .readabilityExtraction: "doc.richtext"
        case .liveWebPage: "globe"
        }
    }

    /// The next source in the cycle, wrapping around.
    var next: ArticleTextSource {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .feed }
        return all[(index + 1) % all.count]
    }

    /// Whether reading from this source requires fetching the page itself.
    var requiresPageFetch: Bool {
        self != .feed
    }
}
