//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
import FeedIngest
@testable import Bulletin

@MainActor
@Suite("Feed store", .serialized)
struct FeedStoreTests {

    private let feedURL = URL(string: "https://example.com/feed.xml")!

    // MARK: - Subscribing

    @Test("Subscribing twice to the same URL does not duplicate the feed")
    func subscribeIsIdempotent() throws {
        // CloudKit mirroring forbids unique constraints, so this is enforced in
        // code and therefore has to be tested rather than assumed.
        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context)

        let first = try store.subscribe(to: feedURL)
        let second = try store.subscribe(to: feedURL)

        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
    }

    // MARK: - Ingest

    @Test("Refreshing ingests articles and fills in feed metadata")
    func ingestsArticles() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: 3))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)

        let summary = try await store.refreshAll()

        #expect(summary.newArticleCount == 3)
        #expect(summary.failedFeedCount == 0)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 3)

        let feed = try #require(try store.feed(withURL: url))
        #expect(feed.title == "Example Blog")
        #expect(feed.homePageURL == URL(string: "https://example.com/"))
    }

    @Test("A title guessed at subscribe time is replaced by the feed's own")
    func refreshCorrectsGuessedTitle() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: 1))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))

        // What discovery hands over for a WordPress site: the boilerplate from
        // a `<link rel="alternate" title="...">` attribute.
        try store.subscribe(to: url, title: "Example » Feed")
        _ = try await store.refreshAll()

        let feed = try #require(try store.feed(withURL: url))
        #expect(feed.title == "Example Blog")
        #expect(feed.displayTitle == "Example Blog")
    }

    @Test("A title the user set themselves survives refreshing")
    func refreshKeepsCustomTitle() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: 1))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        let feed = try store.subscribe(to: url)
        feed.customTitle = "My Name For It"

        _ = try await store.refreshAll()

        // Trusting the feed's own title must not stomp on a rename.
        #expect(feed.displayTitle == "My Name For It")
        #expect(feed.title == "Example Blog")
    }

    @Test("Refreshing the same feed twice does not duplicate articles")
    func ingestDedupsByGUID() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: 3))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)

        _ = try await store.refreshAll()
        let second = try await store.refreshAll()

        // Identity is (feed, guid). Without it, every refresh would re-insert
        // the entire feed and the unread count would climb forever.
        #expect(second.newArticleCount == 0)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 3)
    }

    @Test("Only genuinely new items are inserted when a feed grows")
    func ingestsOnlyNewItems() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        nonisolated(unsafe) var itemCount = 3
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: itemCount))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)

        _ = try await store.refreshAll()
        itemCount = 5
        let second = try await store.refreshAll()

        #expect(second.newArticleCount == 2)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 5)
    }

    @Test("Ingest records a canonical URL for duplicate collapsing")
    func ingestCanonicalizesURLs() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: 1))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)
        _ = try await store.refreshAll()

        let article = try #require(try context.fetch(FetchDescriptor<Article>()).first)
        #expect(article.url?.absoluteString.contains("utm_source") == true)
        // The tracking parameter must be gone from the canonical form, or the
        // same story from two feeds never compares equal.
        #expect(article.canonicalURL == URL(string: "https://example.com/posts/1"))
    }

    @Test("Every ingested article gets a status record")
    func ingestCreatesStatus() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             SampleFeed.rss(itemCount: 2))
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)
        _ = try await store.refreshAll()

        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.allSatisfy { $0.status != nil })
        #expect(articles.allSatisfy { $0.status?.isRead == false })
    }

    // MARK: - Failure handling

    @Test("A failing feed backs off and is skipped by the next refresh")
    func failureBacksOff() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        let session = TestURLProtocol.session { _ in
            (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)

        let first = try await store.refreshAll()
        #expect(first.failedFeedCount == 1)

        let feed = try #require(try store.feed(withURL: url))
        #expect(feed.consecutiveFailureCount == 1)
        #expect(feed.lastFailureMessage != nil)

        // The next ordinary refresh leaves it alone...
        let second = try await store.refreshAll()
        #expect(second.skippedFeedCount == 1)
        #expect(second.failedFeedCount == 0)

        // ...but an explicit request from the user overrides the schedule.
        let forced = try await store.refreshAll(force: true)
        #expect(forced.failedFeedCount == 1)
    }

    @Test("A 304 counts as unchanged and ingests nothing")
    func notModifiedIngestsNothing() async throws {
        defer { TestURLProtocol.reset() }

        let url = feedURL
        nonisolated(unsafe) var status = 200
        let session = TestURLProtocol.session { _ in
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: status == 200 ? ["ETag": "\"v1\""] : nil
            )!
            return (response, status == 200 ? SampleFeed.rss(itemCount: 2) : Data())
        }

        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context, fetcher: FeedFetcher(session: session))
        try store.subscribe(to: url)

        _ = try await store.refreshAll()
        status = 304
        let second = try await store.refreshAll()

        #expect(second.unchangedFeedCount == 1)
        #expect(second.newArticleCount == 0)
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 2)
    }
}

// MARK: - Stream retention

@MainActor
@Suite("Stream retention", .serialized)
struct StreamRetentionTests {

    private func seed(_ context: ModelContext) throws -> [Article] {
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Example")
        context.insert(feed)

        var articles: [Article] = []
        for index in 0..<3 {
            let article = Article(guid: "g\(index)", feed: feed, title: "Article \(index)")
            article.publishedAt = Date(timeIntervalSince1970: TimeInterval(1_000 + index))
            let status = ArticleStatus(article: article)
            context.insert(article)
            context.insert(status)
            article.status = status
            articles.append(article)
        }
        try context.save()
        return articles
    }

    @Test("An article read while you are reading it stays in the Unread stream")
    func readArticleIsRetained() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context)
        library.selectedItem = .builtInStream(.unread)

        library.setRead(true, on: articles[1])

        // Without retention the row disappears out from under the selection and
        // arrowing down the stream lands somewhere unpredictable.
        let visible = try context.fetch(
            ArticleQuery.descriptor(
                for: .builtInStream(.unread),
                retainedArticleIDs: library.retainedArticleIDs
            )
        )
        #expect(visible.count == 3)
        #expect(visible.contains { $0.id == articles[1].id })
    }

    @Test("Leaving the stream and returning clears what was read")
    func retentionClearsOnLeavingStream() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context)
        library.selectedItem = .builtInStream(.unread)
        library.setRead(true, on: articles[1])

        library.selectedItem = .builtInStream(.bookmarked)
        library.selectedItem = .builtInStream(.unread)

        #expect(library.retainedArticleIDs.isEmpty)

        let visible = try context.fetch(
            ArticleQuery.descriptor(
                for: .builtInStream(.unread),
                retainedArticleIDs: library.retainedArticleIDs
            )
        )
        #expect(visible.count == 2)
    }

    @Test("Mark All Read empties the stream rather than retaining everything")
    func markAllReadEmptiesStream() throws {
        let context = try TestStore.makeContext()
        _ = try seed(context)
        let library = Library(modelContext: context)
        library.selectedItem = .builtInStream(.unread)

        library.markAllRead(in: .builtInStream(.unread))

        // Clearing a stream out is the whole point of the command, so nothing
        // is retained.
        #expect(library.retainedArticleIDs.isEmpty)
        let visible = try context.fetch(
            ArticleQuery.descriptor(
                for: .builtInStream(.unread),
                retainedArticleIDs: library.retainedArticleIDs
            )
        )
        #expect(visible.isEmpty)
    }
}
