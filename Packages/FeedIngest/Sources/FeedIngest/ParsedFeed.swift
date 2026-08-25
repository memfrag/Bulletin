//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A feed after parsing, with the differences between the four formats already
/// flattened away.
///
/// Nothing downstream should have to care whether an article arrived as RSS,
/// Atom, JSON Feed or RDF.
public struct ParsedFeed: Sendable, Equatable {

    /// Which format this came from. Kept for diagnostics — the raw feed view in
    /// engineering mode is much easier to read when you know what you are looking at.
    public let format: FeedFormat

    public let title: String

    /// The site the feed belongs to, used for discovery and favicons.
    public let homePageURL: URL?

    public let items: [ParsedFeedItem]

    public init(format: FeedFormat, title: String, homePageURL: URL?, items: [ParsedFeedItem]) {
        self.format = format
        self.title = title
        self.homePageURL = homePageURL
        self.items = items
    }
}

/// A single entry in a feed.
public struct ParsedFeedItem: Sendable, Equatable {

    /// The feed's own identifier for this entry.
    ///
    /// Taken from `<guid>`, `<id>`, JSON Feed's `id`, or RDF's `rdf:about`,
    /// falling back to the entry URL and then to a hash of its content. Unique
    /// only within its feed, which is why ingest dedups on `(feed, guid)`.
    public let guid: String

    public let title: String

    public let author: String?

    public let url: URL?

    /// The entry's own text, which may be a summary, the full content, or
    /// nothing at all depending on how generous the publisher is feeling.
    public let contentHTML: String?

    public let publishedAt: Date?

    public init(
        guid: String,
        title: String,
        author: String? = nil,
        url: URL? = nil,
        contentHTML: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.guid = guid
        self.title = title
        self.author = author
        self.url = url
        self.contentHTML = contentHTML
        self.publishedAt = publishedAt
    }
}
