//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The result of the last refresh.
///
/// Refreshing is manual, so the user is standing there having just asked for it
/// and gets a receipt rather than having to wonder whether anything happened.
struct SidebarFooter: View {

    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 6) {
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
                Task { await library.refreshAll() }
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
