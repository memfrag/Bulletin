//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import FeedIngest

@Suite("Fetching", .serialized)
struct FeedFetcherTests {

    private let feedURL = URL(string: "https://example.com/feed.xml")!

    // MARK: - Conditional GET

    @Test("Stored validators are sent as conditional headers")
    func sendsConditionalHeaders() async throws {
        defer { StubURLProtocol.reset() }

        let url = feedURL
        let body = try Fixture.data("rss.xml")
        let session = StubURLProtocol.session { _ in
            (.stub(url: url, status: 200), body)
        }

        let fetcher = FeedFetcher(session: session)
        _ = await fetcher.fetch(
            url: url,
            validators: FeedValidators(etag: "\"abc\"", lastModified: "Mon, 03 Aug 2026 09:00:00 GMT")
        )

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 03 Aug 2026 09:00:00 GMT")
    }

    @Test("A 304 short-circuits before parsing")
    func handlesNotModified() async throws {
        defer { StubURLProtocol.reset() }

        let url = feedURL
        let session = StubURLProtocol.session { _ in
            (.stub(url: url, status: 304), Data())
        }

        let outcome = await FeedFetcher(session: session).fetch(url: url)

        guard case .notModified = outcome else {
            Issue.record("Expected .notModified, got \(outcome)")
            return
        }
    }

    @Test("Validators from the response are handed back for next time")
    func capturesValidators() async throws {
        defer { StubURLProtocol.reset() }

        let url = feedURL
        let body = try Fixture.data("rss.xml")
        let session = StubURLProtocol.session { _ in
            (.stub(url: url, status: 200, headers: [
                "ETag": "\"v2\"",
                "Last-Modified": "Tue, 04 Aug 2026 12:30:00 GMT"
            ]), body)
        }

        let outcome = await FeedFetcher(session: session).fetch(url: url)

        guard case .fetched(let feed, let validators) = outcome else {
            Issue.record("Expected .fetched, got \(outcome)")
            return
        }
        #expect(feed.title == "Example Blog")
        #expect(validators.etag == "\"v2\"")
        #expect(validators.lastModified == "Tue, 04 Aug 2026 12:30:00 GMT")
    }

    // MARK: - Failure

    @Test("Retry-After in seconds is honored")
    func readsRetryAfterSeconds() async throws {
        defer { StubURLProtocol.reset() }

        let url = feedURL
        let session = StubURLProtocol.session { _ in
            (.stub(url: url, status: 429, headers: ["Retry-After": "120"]), Data())
        }

        let outcome = await FeedFetcher(session: session).fetch(url: url)

        guard case .failed(let error, let retryAfter) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(error == .http(status: 429))
        #expect(retryAfter == 120)
        #expect(error.isTransient)
    }

    @Test("A 404 is permanent, a 503 is not")
    func classifiesFailures() {
        // A feed that is gone should stop being retried; a server having a bad
        // day should not be given up on.
        #expect(FeedFetchError.http(status: 404).isTransient == false)
        #expect(FeedFetchError.http(status: 503).isTransient)
        #expect(FeedFetchError.parsing(.unrecognizedFormat).isTransient == false)
        #expect(FeedFetchError.transport("offline").isTransient)
    }

    @Test("Bytes that are not a feed fail as a parsing error, not a transport one")
    func classifiesParseFailure() async throws {
        defer { StubURLProtocol.reset() }

        let url = feedURL
        let body = try Fixture.data("notafeed.txt")
        let session = StubURLProtocol.session { _ in
            (.stub(url: url, status: 200), body)
        }

        let outcome = await FeedFetcher(session: session).fetch(url: url)

        guard case .failed(let error, _) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(error == .parsing(.unrecognizedFormat))
    }

    // MARK: - Backoff

    @Test("Backoff doubles and then stops")
    func backoffGrowsAndCaps() {
        #expect(FeedFetcher.backoffInterval(afterFailures: 0) == 0)
        #expect(FeedFetcher.backoffInterval(afterFailures: 1) == 60)
        #expect(FeedFetcher.backoffInterval(afterFailures: 2) == 120)
        #expect(FeedFetcher.backoffInterval(afterFailures: 3) == 240)

        // Capped, so a feed that has been dead for months is still retried
        // roughly daily rather than drifting toward never.
        #expect(FeedFetcher.backoffInterval(afterFailures: 20) == 86_400)
    }

    // MARK: - Concurrency

    @Test("Every feed in a batch is fetched exactly once")
    func fetchesEveryFeedInBatch() async throws {
        defer { StubURLProtocol.reset() }

        let body = try Fixture.data("rss.xml")
        let session = StubURLProtocol.session { request in
            (.stub(url: request.url!, status: 200), body)
        }

        let urls = (1...20).map { URL(string: "https://example.com/feed\($0).xml")! }
        let requests = urls.map { (url: $0, validators: FeedValidators()) }

        let outcomes = await FeedFetcher(session: session, maxConcurrentRequests: 6)
            .fetchAll(requests)

        #expect(outcomes.count == urls.count)
        #expect(StubURLProtocol.recordedRequests.count == urls.count)
        #expect(Set(outcomes.keys) == Set(urls))
    }
}
