//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Fetches a page's HTML.
///
/// Sends a browser-ish `Accept` and follows redirects, because a great many
/// sites serve something unhelpful to anything that does not look like a
/// browser asking for a page.
public struct PageFetcher: Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// - Returns: The page HTML and the URL it was finally served from, which is
    ///   the correct base for resolving relative links.
    public func fetch(_ url: URL) async throws -> (html: String, finalURL: URL) {

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ContentExtractionError.fetchFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentExtractionError.fetchFailed("HTTP \(http.statusCode)")
        }

        return (Self.decode(data, response: response), response.url ?? url)
    }

    /// Decodes using the encoding the server declared, falling back to UTF-8.
    ///
    /// Windows-1252 and ISO-8859-1 are still out there in quantity, and reading
    /// them as UTF-8 turns every apostrophe into a replacement character.
    static func decode(_ data: Data, response: URLResponse) -> String {

        if let encodingName = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let string = String(data: data, encoding: encoding) {
                    return string
                }
            }
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        return String(decoding: data, as: UTF8.self)
    }
}
