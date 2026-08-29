//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Which feeds are working, and what the broken ones said.
///
/// The third layer of the failure story: a badge on the sidebar row says
/// something is wrong, the line under the sidebar says how many, and this says
/// which and why. Without it a feed can rot for months — the publisher moves
/// it, the domain lapses — and nothing in a reader would ever mention it.
struct FeedHealthSettingsTab: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeedHealthView()

            Text("A feed is marked as failing only after several attempts in a row, so a server having a bad day does not look like a problem to act on. \u{2318}R always retries everything, backoff included.",
                 comment: "Explanation under the feed health table")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}

// Previews use the mock environment, which only exists in DEBUG builds.
#if DEBUG
#Preview {
    FeedHealthSettingsTab()
        .previewEnvironment()
}
#endif
