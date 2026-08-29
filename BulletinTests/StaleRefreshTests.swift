//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import Bulletin

/// Bulletin does not poll, so returning to the app is the only moment an
/// automatic fetch can happen. These pin down when it does.
@MainActor
@Suite("Refresh on activation")
struct StaleRefreshTests {

    private func settings(hours: Int) -> AppSettings {
        let settings = AppSettings.mock()
        settings.staleRefreshHours = hours
        return settings
    }

    private func hoursAgo(_ hours: Double, from now: Date) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }

    @Test("Eight hours is the default")
    func defaultsToEightHours() {
        #expect(AppSettings.mock().staleRefreshHours == 8)
    }

    @Test("Feeds older than the interval are refreshed")
    func refreshesWhenStale() {
        let now = Date()
        let settings = settings(hours: 8)

        #expect(settings.shouldRefresh(lastAttempt: hoursAgo(9, from: now), now: now))
        #expect(settings.shouldRefresh(lastAttempt: hoursAgo(48, from: now), now: now))
    }

    @Test("Feeds fetched recently are left alone")
    func skipsWhenFresh() {
        let now = Date()
        let settings = settings(hours: 8)

        // Switching to the app and back repeatedly must not refetch every time.
        #expect(!settings.shouldRefresh(lastAttempt: hoursAgo(0.1, from: now), now: now))
        #expect(!settings.shouldRefresh(lastAttempt: hoursAgo(7.9, from: now), now: now))
    }

    @Test("Exactly at the interval counts as stale")
    func refreshesAtTheBoundary() {
        let now = Date()
        #expect(settings(hours: 8).shouldRefresh(lastAttempt: hoursAgo(8, from: now), now: now))
    }

    @Test("Nothing fetched yet is as stale as it gets")
    func refreshesWhenNothingFetched() {
        #expect(settings(hours: 8).shouldRefresh(lastAttempt: nil))
    }

    @Test("Zero means every activation")
    func zeroRefreshesAlways() {
        let now = Date()
        #expect(settings(hours: 0).shouldRefresh(lastAttempt: hoursAgo(0.001, from: now), now: now))
    }

    @Test("Never means never, even after a long absence")
    func neverDisablesIt() {
        let now = Date()
        let settings = settings(hours: AppSettings.neverRefreshOnActivation)

        #expect(!settings.shouldRefresh(lastAttempt: hoursAgo(1000, from: now), now: now))
        // Including the case where nothing has been fetched at all.
        #expect(!settings.shouldRefresh(lastAttempt: nil, now: now))
    }

    @Test("The attempt time is recorded when a refresh starts, not when it ends")
    func recordsAttemptAtStart() async throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        #expect(library.lastRefreshAttemptAt == nil)

        await library.refreshAll()

        // Recorded at the start so the launch refresh and an activation landing
        // at the same moment cannot both decide the feeds are stale.
        let attempt = try #require(library.lastRefreshAttemptAt)
        #expect(abs(attempt.timeIntervalSinceNow) < 5)
    }

    @Test("A second activation right after a refresh does nothing")
    func doesNotRefreshTwiceOnLaunch() async throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let settings = settings(hours: 8)

        await library.refreshAll()
        let firstAttempt = library.lastRefreshAttemptAt

        await library.refreshIfStale(olderThan: settings)

        #expect(library.lastRefreshAttemptAt == firstAttempt)
    }
}
