//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftUI

/// Where feed URLs arrive from outside the app.
///
/// A `bulletin://` link or the Services menu hands the app a URL with no window
/// in mind, and there may be no window open at all. This holds it until a
/// window is there to act on it.
///
/// The app is unsandboxed and ships no Share Extension — see the note on D16 —
/// so this and the Services menu are how subscribing from Safari works.
@Observable @MainActor
final class SubscriptionInbox {

    static let shared = SubscriptionInbox()

    /// A URL waiting to be subscribed to.
    private(set) var pendingURL: URL?

    private init() {}

    /// Accepts a `bulletin://` URL.
    ///
    /// Both `bulletin://subscribe?url=…` and the shorter
    /// `bulletin://example.com/feed.xml` are understood, because people will
    /// write the short one.
    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "bulletin" else { return }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queried = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let feedURL = URL(string: queried) {
            pendingURL = feedURL
            return
        }

        // Strip the scheme and treat the rest as the address.
        let remainder = url.absoluteString
            .replacingOccurrences(of: "bulletin://", with: "", options: [.caseInsensitive, .anchored])
        guard !remainder.isEmpty else { return }

        pendingURL = URL(string: remainder.contains("://") ? remainder : "https://\(remainder)")
    }

    /// Accepts text or a URL from the Services menu.
    func handle(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingURL = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    /// Takes the pending URL, clearing it.
    func take() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

// MARK: - Services

/// The object AppKit sends Services menu messages to.
///
/// - Note: The selector name must match `NSMessage` in `Info.plist`.
final class SubscriptionServiceProvider: NSObject {

    @objc
    func subscribeToFeed(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let url = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)

        guard let url, !url.isEmpty else {
            error.pointee = NSLocalizedString(
                "There was no address to subscribe to.",
                comment: "Services menu error"
            ) as NSString
            return
        }

        MainActor.assumeIsolated {
            SubscriptionInbox.shared.handle(text: url)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
