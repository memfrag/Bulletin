//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import Bulletin

/// Mirroring cannot be exercised without a provisioned CloudKit container, so
/// what is tested here is the part that is ours: how an event turns into
/// something the interface shows.
@MainActor
@Suite("Sync monitor")
struct SyncMonitorTests {

    @Test("With mirroring off, no state is reported at all")
    func disabledWhenMirroringIsOff() {
        let monitor = SyncMonitor(isEnabled: false)

        #expect(monitor.state == .disabled)
        // A status line here would be a permanent, meaningless label in the
        // sidebar of an app that does not sync yet.
        #expect(monitor.state.statusText == nil)
    }

    @Test("An event still running reports as syncing")
    func reportsInProgress() {
        let monitor = SyncMonitor(isEnabled: true)

        monitor.apply(.init(hasFinished: false, endDate: nil, errorMessage: nil, typeDescription: "export"))

        #expect(monitor.state == .syncing)
        #expect(monitor.state.statusText != nil)
    }

    @Test("A successful event says nothing")
    func successIsSilent() {
        let monitor = SyncMonitor(isEnabled: true)
        let finished = Date()

        monitor.apply(.init(hasFinished: true, endDate: finished, errorMessage: nil, typeDescription: "export"))

        #expect(monitor.state == .idle(lastSuccess: finished))
        // Reporting success nobody asked about is just noise.
        #expect(monitor.state.statusText == nil)
        #expect(!monitor.state.isFailing)
    }

    @Test("A failed event is reported and remembered")
    func reportsFailure() {
        let monitor = SyncMonitor(isEnabled: true)

        monitor.apply(.init(hasFinished: true, endDate: Date(), errorMessage: "Network unavailable", typeDescription: "import"))

        #expect(monitor.state.isFailing)
        #expect(monitor.state.statusText != nil)
    }

    @Test("A later success clears an earlier failure")
    func recoversFromFailure() {
        let monitor = SyncMonitor(isEnabled: true)
        monitor.apply(.init(hasFinished: true, endDate: Date(), errorMessage: "Network unavailable", typeDescription: "import"))

        monitor.apply(.init(hasFinished: true, endDate: Date(), errorMessage: nil, typeDescription: "import"))

        // Mirroring retries on its own, so a transient failure must not leave a
        // warning sitting in the sidebar forever.
        #expect(!monitor.state.isFailing)
        #expect(monitor.state.statusText == nil)
    }
}
