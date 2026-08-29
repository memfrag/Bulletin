//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Adding a feed, and the result of the last refresh.
///
/// The add button lives here rather than only in the empty state, because an
/// affordance that disappears once you have one subscription is one you cannot
/// use to get your second.
///
/// Refreshing is manual, so the user is standing there having just asked for it
/// and gets a receipt rather than having to wonder whether anything happened.
struct SidebarFooter: View {

    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 6) {

            Button {
                library.isPresentingSubscribeSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.accessoryBar)
            .help(Text("Add a feed", comment: "Add feed button help"))

            if let syncStatus = library.syncMonitor.state.statusText {
                // Working sync says nothing. This line only appears when there
                // is something the user would want to know.
                if library.syncMonitor.state.isFailing {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                }
                Text(syncStatus)
            } else if library.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing…", comment: "Shown while feeds are being fetched")
            } else if let summary = library.lastRefresh {
                if summary.failedFeedCount > 0 {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text(summary.statusText)
            } else {
                Text("Not refreshed yet", comment: "Shown before the first refresh of the session")
            }

            Spacer(minLength: 0)

            Button {
                // Asking explicitly overrides a failing feed's backoff window.
                Task { await library.refreshAll(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.accessoryBar)
            .disabled(library.isRefreshing)
            .help(Text("Refresh all feeds", comment: "Refresh button help"))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
