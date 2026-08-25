//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

@MainActor
@Suite("Text sources", .serialized)
struct TextSourceTests {

    private func seed(_ context: ModelContext) throws -> (feed: Feed, article: Article) {
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Example")
        context.insert(feed)

        let article = Article(guid: "g1", feed: feed, title: "An Article")
        article.url = URL(string: "https://example.com/posts/one")
        let status = ArticleStatus(article: article)
        context.insert(article)
        context.insert(status)
        article.status = status

        try context.save()
        return (feed, article)
    }

    // MARK: - Resolution

    @Test("An article with no override follows its feed")
    func followsFeedDefault() throws {
        let context = try TestStore.makeContext()
        let (feed, article) = try seed(context)
        let library = Library(modelContext: context)

        #expect(library.textSource(for: article) == .feed)

        feed.textSource = .nativeExtraction
        #expect(library.textSource(for: article) == .nativeExtraction)
    }

    @Test("Cycling sets the feed's default, not just this article's")
    func cyclingSetsFeedDefault() throws {
        let context = try TestStore.makeContext()
        let (feed, article) = try seed(context)
        let library = Library(modelContext: context)

        library.cycleTextSource(for: article)

        // The whole point: a chronically truncated feed is fixed once, not on
        // every article.
        #expect(feed.textSource == .nativeExtraction)
        #expect(article.status?.textSourceOverride == nil)
    }

    @Test("Cycling walks all four sources and wraps")
    func cyclingWrapsAround() throws {
        let context = try TestStore.makeContext()
        let (feed, article) = try seed(context)
        let library = Library(modelContext: context)

        var seen: [ArticleTextSource] = []
        for _ in 0..<4 {
            library.cycleTextSource(for: article)
            seen.append(feed.textSource)
        }

        #expect(seen == [.nativeExtraction, .readabilityExtraction, .liveWebPage, .feed])
    }

    @Test("A per-article override wins over the feed, without changing it")
    func articleOverrideWins() throws {
        let context = try TestStore.makeContext()
        let (feed, article) = try seed(context)
        let library = Library(modelContext: context)
        feed.textSource = .nativeExtraction

        library.setTextSource(.liveWebPage, for: article, scope: .article)

        #expect(library.textSource(for: article) == .liveWebPage)
        #expect(feed.textSource == .nativeExtraction)
    }

    @Test("Setting a feed default clears a stale per-article override")
    func feedScopeClearsOverride() throws {
        let context = try TestStore.makeContext()
        let (_, article) = try seed(context)
        let library = Library(modelContext: context)
        library.setTextSource(.liveWebPage, for: article, scope: .article)

        library.setTextSource(.readabilityExtraction, for: article, scope: .feed)

        // An override left behind here would silently ignore the choice the
        // user just made.
        #expect(article.status?.textSourceOverride == nil)
        #expect(library.textSource(for: article) == .readabilityExtraction)
    }

    @Test("Only the extraction sources need a page fetch")
    func identifiesFetchingSources() {
        #expect(!ArticleTextSource.feed.requiresPageFetch)
        #expect(ArticleTextSource.nativeExtraction.requiresPageFetch)
        #expect(ArticleTextSource.readabilityExtraction.requiresPageFetch)
        #expect(ArticleTextSource.liveWebPage.requiresPageFetch)
    }
}

// MARK: - Body storage

@MainActor
@Suite("Article body storage", .serialized)
struct ArticleBodyStoreTests {

    @Test("Bodies are cached per source, not per article")
    func cachesPerSource() throws {
        let context = try TestStore.makeContext()
        let store = ArticleTextStore(modelContext: context)
        let articleID = UUID()

        context.insert(ArticleBody(
            articleID: articleID,
            source: .nativeExtraction,
            contentHTML: "<p>native</p>",
            plainText: "native"
        ))
        try context.save()

        // The two extractors produce different text for the same article, and
        // switching between them must not serve one as the other.
        #expect(store.cachedBody(articleID: articleID, source: .nativeExtraction)?.plainText == "native")
        #expect(store.cachedBody(articleID: articleID, source: .readabilityExtraction) == nil)
    }

    @Test("Pruning removes old bodies and keeps recent ones")
    func prunesOldBodies() throws {
        let context = try TestStore.makeContext()
        let store = ArticleTextStore(modelContext: context)

        let old = ArticleBody(articleID: UUID(), source: .nativeExtraction, contentHTML: "old", plainText: "old")
        old.extractedAt = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let recent = ArticleBody(articleID: UUID(), source: .nativeExtraction, contentHTML: "new", plainText: "new")
        context.insert(old)
        context.insert(recent)
        try context.save()

        store.pruneBodies(olderThanDays: 30)

        let remaining = try context.fetch(FetchDescriptor<ArticleBody>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.plainText == "new")
    }

    @Test("Pruning leaves article metadata untouched")
    func pruningKeepsMetadata() throws {
        let context = try TestStore.makeContext()
        let store = ArticleTextStore(modelContext: context)

        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Example")
        context.insert(feed)
        let article = Article(guid: "g1", feed: feed, title: "Kept Forever")
        context.insert(article)

        let body = ArticleBody(articleID: article.id, source: .nativeExtraction, contentHTML: "x", plainText: "x")
        body.extractedAt = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        context.insert(body)
        try context.save()

        store.pruneBodies(olderThanDays: 30)

        // Metadata is never pruned, so search and streams stay complete over the
        // whole history even once the text is gone.
        #expect(try context.fetch(FetchDescriptor<Article>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ArticleBody>()).isEmpty)
    }

    @Test("A retention setting of zero means keep everything")
    func zeroRetentionKeepsEverything() throws {
        let context = try TestStore.makeContext()
        let store = ArticleTextStore(modelContext: context)

        let old = ArticleBody(articleID: UUID(), source: .nativeExtraction, contentHTML: "old", plainText: "old")
        old.extractedAt = Date(timeIntervalSince1970: 0)
        context.insert(old)
        try context.save()

        store.pruneBodies(olderThanDays: 0)

        #expect(try context.fetch(FetchDescriptor<ArticleBody>()).count == 1)
    }
}
