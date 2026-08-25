//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import CoreData
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bulletin", category: "Sync")

/// Watches CloudKit mirroring so the app can say whether sync is working.
///
/// Automatic mirroring is silent by design: it succeeds, fails and retries
/// without telling anyone. That is fine until a user's devices disagree and
/// there is nothing anywhere in the app that admits it — so this listens to the
/// events Core Data posts and keeps the last outcome.
///
/// - Note: When mirroring is off, no events arrive and the state stays
///   ``State/disabled``. Nothing here assumes CloudKit is available.
@Observable @MainActor
final class SyncMonitor {

    enum State: Equatable {
        /// Mirroring is not switched on.
        case disabled
        case idle(lastSuccess: Date?)
        case syncing
        case failed(message: String, at: Date)
    }

    private(set) var state: State

    /// Held so the observation is removed with the monitor.
    ///
    /// `nonisolated(unsafe)` because a nonisolated `deinit` cannot touch
    /// main-actor state, and this is only ever written once during `init` on the
    /// main actor and read once during teardown.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(isEnabled: Bool) {
        state = isEnabled ? .idle(lastSuccess: nil) : .disabled
        guard isEnabled else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Neither `Notification` nor `Event` is `Sendable`, so the parts
            // that matter are pulled out here and only plain values cross into
            // the actor.
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            let outcome = Outcome(
                hasFinished: event.endDate != nil,
                endDate: event.endDate,
                errorMessage: event.error?.localizedDescription,
                typeDescription: String(describing: event.type)
            )

            MainActor.assumeIsolated {
                self?.apply(outcome)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Events

    /// The Sendable part of a mirroring event.
    struct Outcome: Sendable {
        var hasFinished: Bool
        var endDate: Date?
        var errorMessage: String?
        var typeDescription: String
    }

    func apply(_ outcome: Outcome) {
        guard outcome.hasFinished else {
            state = .syncing
            return
        }

        if let errorMessage = outcome.errorMessage {
            // Logged rather than surfaced as an alert: a transient network
            // failure is normal and mirroring retries on its own. The Feed
            // Health view is where a persistent problem should show up.
            log.error("Sync \(outcome.typeDescription, privacy: .public) failed: \(errorMessage, privacy: .public)")
            state = .failed(message: errorMessage, at: Date())
        } else {
            state = .idle(lastSuccess: outcome.endDate)
        }
    }
}

// MARK: - Description

extension SyncMonitor.State {

    /// A short line for the interface, or `nil` when there is nothing to say.
    ///
    /// Working sync says nothing at all. An app that reports success it was
    /// never asked about is just noise.
    var statusText: String? {
        switch self {
        case .disabled, .idle:
            nil
        case .syncing:
            String(localized: "Syncing…")
        case .failed:
            String(localized: "Sync failed")
        }
    }

    var isFailing: Bool {
        if case .failed = self { return true }
        return false
    }
}
