//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Fetches feeds, politely.
///
/// Refreshing is manual, so every fetch here is one the user explicitly asked
/// for. That is exactly why the politeness matters: a single ⌘R must not turn
/// into two hundred unconditional GETs.
///
/// - Conditional GET on every request, so unchanged feeds cost a 304.
/// - A bounded number of requests in flight, so a large subscription list does
///   not open two hundred sockets at once.
/// - `Retry-After` is honored, and failures back off exponentially.
public actor FeedFetcher {

    private let session: URLSession
    private let maxConcurrentRequests: Int

    /// - Parameters:
    ///   - session: Injectable so tests can stub responses with `URLProtocol`.
    ///   - maxConcurrentRequests: How many fetches may be in flight at once.
    public init(session: URLSession = .shared, maxConcurrentRequests: Int = 6) {
        self.session = session
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
    }

    /// Fetches and parses a single feed.
    ///
    /// - Parameters:
    ///   - url: The feed's URL.
    ///   - validators: What the last successful fetch returned, if anything.
    public func fetch(url: URL, validators: FeedValidators = .init()) async -> FeedFetchOutcome {

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/atom+xml, application/rss+xml, application/feed+json, application/xml;q=0.9, */*;q=0.8",
                         forHTTPHeaderField: "Accept")

        if let etag = validators.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failed(.transport(error.localizedDescription), retryAfter: nil)
        }

        guard let http = response as? HTTPURLResponse else {
            return .failed(.transport("not an HTTP response"), retryAfter: nil)
        }

        if http.statusCode == 304 {
            return .notModified
        }

        guard (200..<300).contains(http.statusCode) else {
            let retryAfter = Self.retryAfter(from: http)
            return .failed(.http(status: http.statusCode), retryAfter: retryAfter)
        }

        do {
            let feed = try FeedParser.parse(data)
            let newValidators = FeedValidators(
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
            )
            return .fetched(feed, newValidators)
        } catch let error as FeedParsingError {
            return .failed(.parsing(error), retryAfter: nil)
        } catch {
            return .failed(.parsing(.malformed(error.localizedDescription)), retryAfter: nil)
        }
    }

    /// Fetches many feeds with a bounded number in flight.
    ///
    /// Results come back keyed by the URL that produced them, because the order
    /// completions arrive in says nothing useful.
    public func fetchAll(
        _ requests: [(url: URL, validators: FeedValidators)]
    ) async -> [URL: FeedFetchOutcome] {

        var outcomes: [URL: FeedFetchOutcome] = [:]
        var index = 0

        await withTaskGroup(of: (URL, FeedFetchOutcome).self) { group in

            // Prime the group up to the limit, then top it up as each finishes,
            // so there are never more than `maxConcurrentRequests` in flight.
            while index < requests.count, index < maxConcurrentRequests {
                let request = requests[index]
                index += 1
                group.addTask { [self] in
                    (request.url, await fetch(url: request.url, validators: request.validators))
                }
            }

            while let (url, outcome) = await group.next() {
                outcomes[url] = outcome
                if index < requests.count {
                    let request = requests[index]
                    index += 1
                    group.addTask { [self] in
                        (request.url, await fetch(url: request.url, validators: request.validators))
                    }
                }
            }
        }

        return outcomes
    }

    // MARK: - Retry

    /// Reads `Retry-After`, which servers send as either a number of seconds or
    /// an HTTP date.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces) else {
            return nil
        }

        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }

        if let date = W3CDateFormatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }

    /// How long to wait after `failureCount` consecutive failures.
    ///
    /// Doubles each time from a minute, capped at a day. A server that has been
    /// down for a week is not helped by being asked every thirty seconds, and
    /// the user can always force a refresh past the backoff.
    public static func backoffInterval(afterFailures failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        let base: TimeInterval = 60
        // Clamped only to keep `pow` in sane territory; the day ceiling below is
        // what actually bounds the interval.
        let capped = min(failureCount, 20)
        return min(base * pow(2, Double(capped - 1)), 86_400)
    }
}
