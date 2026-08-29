//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FeedKit

/// Turns bytes into a ``ParsedFeed``, whichever of the four formats they are.
///
/// The format is sniffed from the document rather than trusted from the
/// server's `Content-Type`, which is wrong often enough to be useless.
public enum FeedParser {

    /// - Parameter data: The raw feed document.
    /// - Returns: The parsed feed, flattened into a format-neutral shape.
    public static func parse(_ data: Data) throws -> ParsedFeed {

        guard let format = FeedFormat.detect(from: data) else {
            throw FeedParsingError.unrecognizedFormat
        }

        switch format {
        case .rdf:
            return try RDFFeedParser.parse(data)

        case .rss:
            do {
                return map(try RSSFeed(data: data))
            } catch {
                throw FeedParsingError.malformed(String(describing: error))
            }

        case .atom:
            do {
                return map(try AtomFeed(data: data))
            } catch {
                throw FeedParsingError.malformed(String(describing: error))
            }

        case .json:
            do {
                return map(try JSONFeed(data: data))
            } catch {
                throw FeedParsingError.malformed(String(describing: error))
            }
        }
    }

    // MARK: - RSS 2.0

    private static func map(_ feed: RSSFeed) -> ParsedFeed {
        let channel = feed.channel

        let items = (channel?.items ?? []).map { item -> ParsedFeedItem in
            let link = item.link?.trimmed
            return ParsedFeedItem(
                // `<guid>` is optional and frequently absent. The link is the
                // usual stand-in; the title is a last resort so that an item is
                // never silently dropped for lacking an identifier.
                guid: item.guid?.text?.trimmed.nilIfEmpty
                    ?? link?.nilIfEmpty
                    ?? item.title?.trimmed
                    ?? "",
                title: item.title?.asPlainText ?? "",
                author: (item.author ?? item.dublinCore?.creator)?.asPlainText.nilIfEmpty,
                url: url(link),
                // `content:encoded` carries the full post when the publisher is
                // generous; `<description>` is usually the truncated summary.
                contentHTML: item.content?.encoded?.nilIfEmpty ?? item.description?.nilIfEmpty,
                publishedAt: item.pubDate ?? item.dublinCore?.date
            )
        }

        return ParsedFeed(
            format: .rss,
            title: channel?.title?.asPlainText ?? "",
            homePageURL: url(channel?.link),
            items: items
        )
    }

    // MARK: - Atom

    private static func map(_ feed: AtomFeed) -> ParsedFeed {

        let items = (feed.entries ?? []).map { entry -> ParsedFeedItem in
            let link = alternateLink(in: entry.links)
            return ParsedFeedItem(
                guid: entry.id?.trimmed.nilIfEmpty ?? link ?? entry.title?.trimmed ?? "",
                title: entry.title?.asPlainText ?? "",
                author: entry.authors?.first?.name?.asPlainText.nilIfEmpty,
                url: url(link),
                contentHTML: entry.content?.text?.nilIfEmpty ?? entry.summary?.text?.nilIfEmpty,
                // Atom's `published` is optional and `updated` is not, so a feed
                // that only ever edits entries still sorts sensibly.
                publishedAt: entry.published ?? entry.updated
            )
        }

        return ParsedFeed(
            format: .atom,
            title: feed.title?.text?.asPlainText ?? "",
            homePageURL: url(alternateLink(in: feed.links)),
            items: items
        )
    }

    /// The `rel="alternate"` href, which is the human-readable page.
    ///
    /// A link with no `rel` defaults to `alternate` per the Atom spec, so it is
    /// accepted too. `rel="self"` points back at the feed and must not be used.
    private static func alternateLink(in links: [AtomFeedLink]?) -> String? {
        guard let links else { return nil }
        let preferred = links.first { link in
            let rel = link.attributes?.rel
            return rel == nil || rel == "alternate"
        }
        return (preferred ?? links.first)?.attributes?.href?.trimmed.nilIfEmpty
    }

    // MARK: - JSON Feed

    private static func map(_ feed: JSONFeed) -> ParsedFeed {

        let feedAuthorName: String? = feed.author?.name

        let items = (feed.items ?? []).map { item -> ParsedFeedItem in
            let itemURL: String? = item.url?.trimmed
            let identifier: String = item.id?.trimmed.nilIfEmpty ?? itemURL ?? ""
            let authorName: String? = item.author?.name ?? feedAuthorName
            let content: String? = item.contentHtml?.nilIfEmpty
                ?? item.contentText?.nilIfEmpty
                ?? item.summary?.nilIfEmpty
            return ParsedFeedItem(
                guid: identifier,
                title: item.title?.asPlainText ?? "",
                author: authorName?.asPlainText.nilIfEmpty,
                url: url(itemURL),
                contentHTML: content,
                publishedAt: item.datePublished ?? item.dateModified
            )
        }

        return ParsedFeed(
            format: .json,
            title: feed.title?.asPlainText ?? "",
            homePageURL: url(feed.homePageURL),
            items: items
        )
    }
}

// MARK: - Helpers

private extension FeedParser {

    /// Builds a URL from a feed's string, tolerating whitespace and absence.
    static func url(_ string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }
}

private extension String {

    /// Trimmed, with character references decoded.
    ///
    /// Applied to titles and bylines only. Article content is real markup and
    /// decoding its entities would corrupt it.
    var asPlainText: String {
        HTMLEntities.decode(trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
