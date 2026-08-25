//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// A subscribed feed.
///
/// - Important: This model is mirrored to CloudKit, so every property must be
///   optional or carry a default and no property may be marked `@Attribute(.unique)`.
///   Uniqueness of `feedURL` is enforced by the store when subscribing, not by
///   the schema.
///
@Model
final class Feed {

    /// Stable identity, generated locally and preserved across sync.
    var id: UUID = UUID()

    /// The URL the feed itself is fetched from.
    var feedURL: URL?

    /// The site the feed belongs to, used for discovery and favicons.
    var homePageURL: URL?

    var title: String = ""

    /// A user-supplied title, which wins over `title` when present.
    var customTitle: String?

    /// The folder this feed sits in. A feed has exactly one parent; `nil` means
    /// it sits at the root of the subscription tree.
    var folder: Folder?

    /// Which of the four text sources this feed defaults to.
    ///
    /// Stored as the raw value so that a future case added on another device
    /// does not fail to decode here.
    var textSourceRawValue: String = ArticleTextSource.feed.rawValue

    var subscribedAt: Date = Date()

    // MARK: Fetch bookkeeping
    //
    // These describe the *local* fetch state. They ride along in the synced
    // store because they are small and it is convenient for a second device to
    // know a feed has been failing, but they are advisory, not authoritative.

    var lastFetchedAt: Date?

    /// Consecutive failures. A feed is shown as stale past a threshold, so a
    /// transient 503 does not read as a problem the user must act on.
    var consecutiveFailureCount: Int = 0

    var lastFailureMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article]? = []

    init(feedURL: URL, title: String = "", homePageURL: URL? = nil) {
        self.id = UUID()
        self.feedURL = feedURL
        self.title = title
        self.homePageURL = homePageURL
        self.subscribedAt = Date()
    }
}

// MARK: - Convenience

extension Feed {

    /// How many consecutive failures before a feed is shown as stale.
    ///
    /// A transient 503 must not read as a problem the user has to act on, and a
    /// feed that has been dead for a week must not stay silent. Three is a
    /// placeholder pending real use.
    static let staleFailureThreshold = 3

    /// Whether this feed has failed often enough to be worth flagging.
    var isStale: Bool {
        consecutiveFailureCount >= Self.staleFailureThreshold
    }

    /// The title to show in the UI.
    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }
        if !title.isEmpty {
            return title
        }
        return feedURL?.host() ?? String(localized: "Untitled Feed")
    }

    /// The text source this feed's articles open with.
    var textSource: ArticleTextSource {
        get { ArticleTextSource(rawValue: textSourceRawValue) ?? .feed }
        set { textSourceRawValue = newValue.rawValue }
    }
}
