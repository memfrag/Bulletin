//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import KeyValueStore

// MARK: - AppSettings

/// A container for application-wide user settings.
///
/// `AppSettings` provides observable properties that represent user preferences
/// and persists them using an underlying key–value store.
/// It is designed to be injected into SwiftUI views and other components
/// that depend on reactive settings.
///
@Observable @MainActor public final class AppSettings {

    // MARK: Key

    /// The keys used to store and retrieve settings from the underlying store.
    public enum Key: String {
        /// The preferred color scheme for the app.
        case colorScheme

        // MARK: Reader

        case readerFontSize
        case readerLineWidth
        case readerUsesSerif

        // MARK: Refreshing

        case staleRefreshHours

        // MARK: Storage

        case bodyRetentionDays
    }

    // MARK: Properties

    /// The app's current color scheme preference.
    public var colorScheme: AppColorScheme {
        didSet {
            store.save(colorScheme, for: .colorScheme)
        }
    }

    // MARK: Reader

    /// Body text size in the reader, in points.
    public var readerFontSize: Double {
        didSet {
            store.save(readerFontSize, for: .readerFontSize)
        }
    }

    /// The text column's maximum width, in points.
    ///
    /// A measure of roughly 70 characters is where long-form text stops being
    /// tiring, which is what the default is set to.
    public var readerLineWidth: Double {
        didSet {
            store.save(readerLineWidth, for: .readerLineWidth)
        }
    }

    public var readerUsesSerif: Bool {
        didSet {
            store.save(readerUsesSerif, for: .readerUsesSerif)
        }
    }

    // MARK: Refreshing

    /// How stale the feeds may be before activating the app refreshes them.
    ///
    /// There is no polling timer — macOS gives a quit app no background refresh
    /// anyway — so coming back to the app is the moment worth checking. A value
    /// of `0` refreshes on every activation; ``neverRefreshOnActivation``
    /// disables it entirely.
    public var staleRefreshHours: Int {
        didSet {
            store.save(staleRefreshHours, for: .staleRefreshHours)
        }
    }

    /// The value of ``staleRefreshHours`` that means "only when I ask".
    public static let neverRefreshOnActivation = -1

    /// Whether activating the app should refresh feeds this old.
    public func shouldRefresh(lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard staleRefreshHours != Self.neverRefreshOnActivation else { return false }

        // Nothing fetched yet this session is as stale as it gets.
        guard let lastAttempt else { return true }

        let elapsed = now.timeIntervalSince(lastAttempt)
        return elapsed >= TimeInterval(staleRefreshHours) * 3600
    }

    // MARK: Storage

    /// How long an extracted article body is kept before being evicted.
    ///
    /// Metadata is never pruned — only the heavy text — so search and streams
    /// stay complete over the whole history while the store stays bounded.
    public var bodyRetentionDays: Int {
        didSet {
            store.save(bodyRetentionDays, for: .bodyRetentionDays)
        }
    }

    // MARK: Setup

    /// The key–value store that backs this settings container.
    @ObservationIgnored
    private let store: AnyKeyValueStore<AppSettings.Key>

    /// Creates a new instance of `AppSettings`.
    ///
    /// - Parameter store: The store used to persist values. If `nil`,
    ///   defaults to a `UserDefaults`-backed store.
    ///
    public init(store: AnyKeyValueStore<AppSettings.Key>? = nil) {
        self.store = store ?? .defaultStore
        colorScheme = self.store.load(.colorScheme, default: .system)
        readerFontSize = self.store.load(.readerFontSize, default: 17)
        readerLineWidth = self.store.load(.readerLineWidth, default: 680)
        readerUsesSerif = self.store.load(.readerUsesSerif, default: false)
        staleRefreshHours = self.store.load(.staleRefreshHours, default: 8)
        bodyRetentionDays = self.store.load(.bodyRetentionDays, default: 30)
    }
}
