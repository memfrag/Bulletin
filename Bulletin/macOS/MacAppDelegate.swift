//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

class MacAppDelegate: NSObject, NSApplicationDelegate {

    /// Held for as long as the app runs, because AppKit does not retain it.
    private let subscriptionServiceProvider = SubscriptionServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registers "Subscribe in Bulletin" in every app's Services menu, which
        // is how a feed gets added from Safari without a Share Extension.
        NSApplication.shared.servicesProvider = subscriptionServiceProvider
        NSUpdateDynamicServices()
    }
    
    // Sparkle may show its update-permission prompt before the main window
    // appears. If that prompt is the only open window, closing it would
    // otherwise terminate the app before it has even started.
    static var shouldTerminateAppAfterLastWindowClosed = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.shouldTerminateAppAfterLastWindowClosed
    }

    /// Called at quit so that coalesced reading state is written.
    ///
    /// Status writes are batched, so up to a couple of seconds of "I read
    /// this" can be sitting in memory when the user quits. Losing it silently
    /// looks like the app forgetting what you just read.
    static var flushPendingWrites: (@MainActor () -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.flushPendingWrites?()
        }
    }
}

// MARK: - Terminates App When Closed Modifier

extension View {

    /// Marks this view as the main window for the purposes of
    /// `applicationShouldTerminateAfterLastWindowClosed`. Once the view has
    /// appeared at least once, the app is allowed to terminate when the last
    /// window closes.
    func terminatesAppWhenClosed() -> some View {
        onAppear {
            MacAppDelegate.shouldTerminateAppAfterLastWindowClosed = true
        }
    }
}
