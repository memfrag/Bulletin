//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Reduces a URL to the identity of the thing it points at.
///
/// Two feeds carrying the same story hand out URLs that differ only in tracking
/// parameters, scheme, `www.`, or a trailing slash. Normalizing those away is
/// what lets the article list collapse duplicates without mutating anything or
/// guessing at title similarity.
///
/// This is deliberately conservative: it only strips parameters that are known
/// to be tracking, never ones that might select content. A false merge hides an
/// article the user wanted, which is much worse than showing a duplicate.
public enum CanonicalURL {

    /// Query parameter names that never affect which document you get.
    private static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_brand", "utm_social",
        "utm_social-type", "utm_place",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "twclid",
        "mc_cid", "mc_eid", "igshid", "ref_src", "ref_url",
        "_hsenc", "_hsmi", "hsCtaTracking",
        "at_medium", "at_campaign", "at_custom1", "at_custom2",
        "source", "ref", "cmpid", "CMP", "spm"
    ]

    /// Normalizes a URL for identity comparison.
    ///
    /// - Note: The result is for *comparison*, not for navigation. It lowercases
    ///   the host and drops the fragment, so it is not necessarily a URL you
    ///   would want to open.
    public static func canonicalize(_ url: URL) -> URL? {

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // http and https serve the same article; pick one so they compare equal.
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        } else {
            components.scheme = components.scheme?.lowercased()
        }

        if let host = components.host?.lowercased() {
            components.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }

        // A default port and no port are the same address.
        if let port = components.port,
           (components.scheme == "https" && port == 443) || (components.scheme == "http" && port == 80) {
            components.port = nil
        }

        if let queryItems = components.queryItems {
            let kept = queryItems.filter { !trackingParameters.contains($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        // Fragments address a position within a document, not a document.
        components.fragment = nil

        // `/post/` and `/post` are the same page everywhere that matters, but
        // the root path is left alone — "https://example.com" needs its slash.
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        return components.url
    }
}
