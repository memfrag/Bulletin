//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The HTTP validators a previous fetch handed back.
///
/// Sending these on the next request is what turns a refresh of two hundred
/// feeds into two hundred 304s and almost no traffic.
public struct FeedValidators: Sendable, Equatable {

    public var etag: String?
    public var lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// What came back from trying to fetch a feed.
public enum FeedFetchOutcome: Sendable {

    /// The server said nothing has changed. Nothing was parsed and nothing
    /// needs to be.
    case notModified

    /// A new copy of the feed.
    case fetched(ParsedFeed, FeedValidators)

    /// It did not work. Carries how long to wait before trying again.
    case failed(FeedFetchError, retryAfter: TimeInterval?)
}

/// Why a fetch failed.
public enum FeedFetchError: Error, Sendable, Equatable {

    case transport(String)

    /// A 4xx or 5xx.
    case http(status: Int)

    /// The bytes arrived but were not a feed.
    case parsing(FeedParsingError)
}

extension FeedFetchError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .transport(let detail):
            String(localized: "Could not reach the server: \(detail)")
        case .http(let status):
            String(localized: "The server responded \(status).")
        case .parsing(let error):
            error.errorDescription
        }
    }

    /// Whether this is worth retrying automatically.
    ///
    /// A 404 means the feed is gone and retrying it forever is just noise; a 503
    /// means come back later.
    public var isTransient: Bool {
        switch self {
        case .transport: true
        case .http(let status): status == 408 || status == 429 || status >= 500
        case .parsing: false
        }
    }
}
