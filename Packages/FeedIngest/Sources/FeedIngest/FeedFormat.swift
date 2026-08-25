//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The feed formats the app can read.
///
/// Text formats only. Enclosures are not modelled, so podcast and video feeds
/// parse as ordinary articles rather than as media.
public enum FeedFormat: String, Sendable, CaseIterable {

    /// RSS 2.0, and the various 0.9x dialects that parse the same way.
    case rss

    /// The Atom Syndication Format.
    case atom

    /// JSON Feed.
    case json

    /// RSS 1.0, the RDF-based flavour. Still emitted by long-lived blogs and
    /// academic sites, and structurally unlike RSS 2.0 — items are siblings of
    /// the channel rather than children of it.
    case rdf
}

// MARK: - Detection

extension FeedFormat {

    /// The number of bytes to inspect when sniffing a document.
    ///
    /// Generous on purpose: a feed can open with a long XML declaration, a
    /// stylesheet processing instruction and a licence comment before the root
    /// element ever appears.
    private static let inspectionPrefixLength = 4096

    /// Sniffs the format from the head of a document.
    ///
    /// - Returns: The detected format, or `nil` if this does not look like a feed.
    public static func detect(from data: Data) -> FeedFormat? {

        let head = String(decoding: data.prefix(inspectionPrefixLength), as: UTF8.self)
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{") {
            return .json
        }

        // RDF must be checked before RSS: an RSS 1.0 document mentions "rss" in
        // its default namespace URI, so a naive contains("<rss") is not enough
        // and a naive contains("rss") would misfile it.
        if head.contains("<rdf:RDF") || head.contains("<RDF") {
            return .rdf
        }

        if head.contains("<rss") {
            return .rss
        }

        if head.contains("<feed") {
            return .atom
        }

        return nil
    }
}
