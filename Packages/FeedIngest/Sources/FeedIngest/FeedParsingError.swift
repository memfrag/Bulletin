//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Why a document could not be turned into a feed.
///
/// These are surfaced per-feed in the Feed Health view rather than as alerts:
/// one publisher emitting broken XML is not something the reader should stop
/// for.
public enum FeedParsingError: Error, Equatable, Sendable {

    /// The document does not look like any format we read.
    case unrecognizedFormat

    /// It looked like a feed but would not parse.
    case malformed(String)

    /// It parsed, but there was no feed in it.
    case empty
}

extension FeedParsingError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            String(localized: "This does not look like an RSS, Atom, JSON or RDF feed.")
        case .malformed(let detail):
            String(localized: "The feed could not be parsed: \(detail)")
        case .empty:
            String(localized: "The feed parsed but contained nothing.")
        }
    }
}
