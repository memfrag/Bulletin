//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    let updater: SPUUpdater

    var body: some Scene {

        WindowGroup {
            MainWindowContent()
                .frame(minWidth: 760, minHeight: 480)
                .appEnvironment(.default)
                #if os(macOS)
                .terminatesAppWhenClosed()
                #endif
        }
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            SidebarCommands()
            HelpCommands()
            BulletinCommands()
        }
    }
}

// MARK: - Content

/// Owns the window's reading session.
///
/// One `Library` per window, created from the shared container, so two windows
/// can sit on different streams while writing to the same store.
private struct MainWindowContent: View {

    @Environment(AppSettings.self) private var settings

    @State private var library = Library(modelContainer: AppEnvironment.default.modelContainer)

    var body: some View {
        Sidebar()
            .environment(library)
            .onOpenURL { url in
                SubscriptionInbox.shared.handle(url)
            }
            .onChange(of: SubscriptionInbox.shared.pendingURL) { _, url in
                guard url != nil else { return }
                library.isPresentingSubscribeSheet = true
            }
            // Set at the window root so the menu commands can find it whatever
            // has focus inside the window.
            .focusedSceneValue(\.library, library)
            .onAppear {
                // Reading state is written in batches, so quitting has to be
                // able to force the last one out.
                MacAppDelegate.flushPendingWrites = { [weak library] in
                    library?.flushPendingWrites()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                // Coming back to the app is the only moment an automatic fetch
                // is clearly wanted; there is no polling timer to lean on.
                Task { await library.refreshIfStale(olderThan: settings) }
            }
            .task {
                // Evict bodies past the retention window. Metadata is never
                // pruned, so search and streams stay complete either way.
                library.pruneBodies(retentionDays: settings.bodyRetentionDays)

                // Streams and search are answered from the index, so it has to
                // agree with the store before anything can be found.
                library.prepareIndex()

                // Refresh on launch. There is no timer: macOS gives a quit app
                // no background refresh anyway, and this is the politest thing
                // to do to a few hundred publishers.
                await library.refreshAll()
            }
    }
}
