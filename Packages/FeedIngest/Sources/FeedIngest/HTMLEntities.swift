//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Decodes the character references that turn up in feeds.
///
/// Feed titles arrive from two places that escape differently. A feed's own
/// `<title>` is XML, so it carries only the five XML entities. A title lifted
/// from a page's `<link rel="alternate" title="...">` is HTML, and WordPress in
/// particular writes things like `SwiftLee &raquo; Feed`.
///
/// Rather than a full HTML entity table — there are well over a thousand — this
/// covers numeric references, which are unbounded and the common case, plus the
/// named ones that actually appear in titles.
public enum HTMLEntities {

    /// Named references worth knowing, beyond the five XML ones.
    ///
    /// Punctuation publishers use in titles: separators, dashes, quotes and
    /// the symbols that end up in site names.
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "raquo": "»", "laquo": "«", "rsaquo": "›", "lsaquo": "‹",
        "hellip": "…", "mdash": "—", "ndash": "–", "minus": "−",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "sbquo": "‚", "bdquo": "„", "prime": "′", "Prime": "″",
        "bull": "•", "middot": "·", "sect": "§", "para": "¶", "dagger": "†",
        "copy": "©", "reg": "®", "trade": "™",
        "deg": "°", "plusmn": "±", "times": "×", "divide": "÷", "frac12": "½",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢",
        "ldquor": "„", "shy": "\u{00AD}", "ensp": "\u{2002}", "emsp": "\u{2003}",
        "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}"
    ]

    /// Replaces every character reference in a string.
    ///
    /// Unknown references are left exactly as they were: showing `&foo;` is
    /// less confusing than silently deleting it, and it makes the gap visible
    /// if one ever matters.
    public static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = ""
        result.reserveCapacity(string.count)

        var remainder = Substring(string)

        while let ampersand = remainder.firstIndex(of: "&") {
            result.append(contentsOf: remainder[remainder.startIndex..<ampersand])

            let afterAmpersand = remainder.index(after: ampersand)
            // A reference is at most a handful of characters; scanning further
            // than that means this ampersand is just an ampersand.
            let searchEnd = remainder.index(afterAmpersand, offsetBy: 12, limitedBy: remainder.endIndex)
                ?? remainder.endIndex

            guard let semicolon = remainder[afterAmpersand..<searchEnd].firstIndex(of: ";") else {
                result.append("&")
                remainder = remainder[afterAmpersand...]
                continue
            }

            let reference = String(remainder[afterAmpersand..<semicolon])

            if let decoded = decodeReference(reference) {
                result.append(decoded)
            } else {
                result.append("&\(reference);")
            }

            remainder = remainder[remainder.index(after: semicolon)...]
        }

        result.append(contentsOf: remainder)
        return result
    }

    private static func decodeReference(_ reference: String) -> String? {
        guard !reference.isEmpty else { return nil }

        if reference.hasPrefix("#") {
            let digits = reference.dropFirst()
            let scalarValue: UInt32?

            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits, radix: 10)
            }

            guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else { return nil }
            return String(Character(scalar))
        }

        return named[reference]
    }
}
