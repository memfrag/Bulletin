//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// What this machine knows about fetching a given feed.
///
/// HTTP validators are per-machine — another device's `ETag` says nothing about
/// what is in *this* device's store — so they stay local and out of sync.
///
/// - Note: Lives in the local store and keys by `feedID`; see ``ArticleBody``.
///
@Model
final class FeedFetchState {

    var feedID: UUID = UUID()

    var etag: String?

    var lastModified: String?

    var lastFetchedAt: Date?

    /// Set after a failure. The feed is skipped until this passes, so a server
    /// having a bad day is not hammered on every manual refresh.
    var backoffUntil: Date?

    var consecutiveFailureCount: Int = 0

    init(feedID: UUID) {
        self.feedID = feedID
    }
}
