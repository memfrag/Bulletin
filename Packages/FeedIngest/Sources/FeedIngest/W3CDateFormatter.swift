//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Parses the date formats feeds actually use, as opposed to the ones they
/// claim to.
///
/// RSS 1.0 specifies W3CDTF and RSS 2.0 specifies RFC 822, but publishers emit
/// both from either, along with several near-misses. Every format is tried
/// rather than trusting the feed's declared type.
/// - Note: The formatters below are `nonisolated(unsafe)` deliberately.
///   Foundation documents `DateFormatter` and `ISO8601DateFormatter` as safe for
///   concurrent use once configured, and these are configured once at
///   initialization and never mutated again. Building them per call instead
///   would mean nine allocations per feed item on every refresh.
enum W3CDateFormatter {

    private nonisolated(unsafe) static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Formats that `ISO8601DateFormatter` will not take.
    private static let fallbackFormats = [
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
        "EEE, dd MMM yyyy HH:mm:ss ZZZ",   // RFC 822
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm ZZZ",
        "dd MMM yyyy HH:mm:ss ZZZ"
    ]

    private static let fallbackFormatters: [DateFormatter] = fallbackFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = iso8601WithFractionalSeconds.date(from: trimmed) { return date }
        if let date = iso8601.date(from: trimmed) { return date }

        for formatter in fallbackFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        return nil
    }
}
