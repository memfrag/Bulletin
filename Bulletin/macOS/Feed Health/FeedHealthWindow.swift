//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Where a feed that has stopped working says so.
///
/// The third layer of the failure story: a badge on the row says something is
/// wrong, the post-refresh line says how many, and this says which and why. A
/// feed can rot for months otherwise — the publisher moves it, the domain
/// lapses — and nothing in a reader would ever mention it.
struct FeedHealthWindow: Scene {

    static let windowID = "feed-health"

    var body: some Scene {
        Window(Text("Feed Health", comment: "Feed health window title"), id: Self.windowID) {
            FeedHealthView()
                .appEnvironment(.default)
        }
        .defaultPosition(.center)
        .defaultSize(width: 620, height: 440)
    }
}
