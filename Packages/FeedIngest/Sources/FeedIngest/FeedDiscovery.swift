//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A feed advertised by a web page.
public struct DiscoveredFeed: Sendable, Equatable {

    public let url: URL

    /// The `title` attribute of the `<link>`, which is how a site distinguishes
    /// "Main feed" from "Comments" from "Podcast".
    public let title: String?

    public let format: FeedFormat?

    public init(url: URL, title: String?, format: FeedFormat?) {
        self.url = url
        self.title = title
        self.format = format
    }
}

/// Finds the feeds behind a URL.
///
/// Subscribing should accept whatever the user has in their clipboard — usually
/// a site's homepage, not a feed URL, because nobody keeps feed URLs around.
public enum FeedDiscovery {

    /// `<link rel="alternate">` types that mean "this is a feed".
    private static let feedTypes: [String: FeedFormat] = [
        "application/rss+xml": .rss,
        "application/atom+xml": .atom,
        "application/feed+json": .json,
        "application/json": .json,
        "application/rdf+xml": .rdf,
        "text/xml": .rss
    ]

    /// Discovers the feeds a URL offers.
    ///
    /// If the URL is itself a feed, that feed is returned alone — pasting a real
    /// feed URL should not send us hunting through HTML.
    ///
    /// - Returns: Every feed found, in document order. Empty if there are none.
    public static func discover(at url: URL, session: URLSession = .shared) async throws -> [DiscoveredFeed] {

        var request = URLRequest(url: url)
        request.setValue("text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8",
                         forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        // The URL we actually landed on after redirects is the right base for
        // resolving relative hrefs.
        let baseURL = response.url ?? url

        if let format = FeedFormat.detect(from: data) {
            let title = try? FeedParser.parse(data).title
            return [DiscoveredFeed(url: baseURL, title: title, format: format)]
        }

        return feedLinks(inHTML: String(decoding: data, as: UTF8.self), baseURL: baseURL)
    }

    /// Extracts feed `<link>` elements from HTML.
    ///
    /// Exposed for testing so discovery can be checked against fixture pages
    /// without a network.
    ///
    /// - Note: Uses a regular expression rather than a real HTML parser. That is
    ///   a poor idea in general, but `<link>` elements are void elements in
    ///   `<head>` with no nesting, which is the one shape regex handles safely.
    public static func feedLinks(inHTML html: String, baseURL: URL?) -> [DiscoveredFeed] {

        // Only scan the head; a page body can contain anything.
        let scope = html.range(of: "</head>", options: [.caseInsensitive]).map {
            String(html[html.startIndex..<$0.lowerBound])
        } ?? html

        let pattern = #"<link\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(scope.startIndex..<scope.endIndex, in: scope)
        var discovered: [DiscoveredFeed] = []
        var seen: Set<URL> = []

        regex.enumerateMatches(in: scope, range: range) { match, _, _ in
            guard let match, let matchRange = Range(match.range, in: scope) else { return }
            let tag = String(scope[matchRange])

            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.split(separator: " ").contains("alternate") else {
                return
            }

            guard let type = attribute("type", in: tag)?.lowercased(),
                  let format = feedTypes[type] else {
                return
            }

            guard let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  !seen.contains(url) else {
                return
            }

            seen.insert(url)
            discovered.append(
                DiscoveredFeed(url: url, title: attribute("title", in: tag), format: format)
            )
        }

        return discovered
    }

    /// Reads one attribute out of a tag, handling single quotes, double quotes
    /// and HTML entities in the value.
    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }

        for group in 2...3 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range]).decodingBasicHTMLEntities
            }
        }
        return nil
    }
}

// MARK: - Helpers

private extension String {

    /// Decodes the handful of entities that actually turn up in `href`s.
    var decodingBasicHTMLEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
