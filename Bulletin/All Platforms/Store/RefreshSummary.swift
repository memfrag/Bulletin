//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// What one refresh did.
///
/// Refreshing is manual, so the user is standing there having just asked for it
/// and gets a receipt: "142 new · 2 feeds failed".
struct RefreshSummary: Sendable, Equatable {

    var newArticleCount: Int = 0

    /// Feeds the server said were unchanged. Not shown, but worth having when
    /// diagnosing why a refresh found nothing.
    var unchangedFeedCount: Int = 0

    var refreshedFeedCount: Int = 0

    var failedFeedCount: Int = 0

    var finishedAt: Date = Date()

    /// Feeds skipped because they are still inside their backoff window.
    var skippedFeedCount: Int = 0
}

extension RefreshSummary {

    /// The one-line receipt shown after a refresh.
    var statusText: String {
        if failedFeedCount > 0 {
            return String(localized: "\(newArticleCount) new · \(failedFeedCount) feeds failed")
        }
        if newArticleCount == 0 {
            return String(localized: "Up to date")
        }
        return String(localized: "\(newArticleCount) new")
    }
}
