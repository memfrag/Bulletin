//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// Reading down a stream changes status on nearly every keystroke, and each
/// search-index update is a transaction with an FTS delete and insert in it.
///
/// The **index** is batched; the **store** never is. Deferring `save()` was
/// tried and reverted: SwiftData's fetches do not reflect unsaved changes
/// through the status relationship, so the article list showed stale read state
/// — the exact thing marking-on-read exists to avoid. These tests pin both
/// halves of that down.
@MainActor
@Suite("Coalesced writes", .serialized)
struct CoalescedWriteTests {

    private func seed(_ context: ModelContext) throws -> [Article] {
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Example")
        context.insert(feed)

        var articles: [Article] = []
        for index in 0..<5 {
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

    @Test("The store is written immediately, so the list never shows stale state")
    func storeIsNeverDeferred() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.setRead(true, on: articles[0])

        // This is the regression that reverted deferred saves: a fetch through
        // the status relationship does not see unsaved changes, so the article
        // list kept showing the article as unread until the batch flushed.
        #expect(!context.hasChanges)

        let unread = try context.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.status?.isRead == false })
        )
        #expect(unread.count == 4)
    }

    @Test("Index updates are batched rather than written per article")
    func batchesIndexUpdates() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        for article in articles {
            library.setRead(true, on: article)
        }

        // Five status changes, one pending index write.
        #expect(library.hasPendingWrites)

        library.flushPendingWrites()

        #expect(!library.hasPendingWrites)
        #expect(articles.allSatisfy { $0.status?.isRead == true })
    }

    @Test("Flushing clears everything that was waiting")
    func flushClearsPending() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.setRead(true, on: articles[0])
        library.toggleStarred(articles[1])
        library.flushPendingWrites()

        #expect(!library.hasPendingWrites)
        #expect(!context.hasChanges)
    }

    @Test("A note is written straight away rather than batched")
    func notesAreNotDeferred() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.setNote("Worth revisiting", on: articles[0])

        // A note is typed deliberately and is not about to be replaced a second
        // later, so its index row is written straight away too.
        #expect(!context.hasChanges)
        #expect(!library.hasPendingWrites)
        #expect(articles[0].status?.note == "Worth revisiting")
    }

    @Test("Marking a whole stream read is written as one deliberate act")
    func markAllReadWritesImmediately() throws {
        let context = try TestStore.makeContext()
        _ = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)
        library.selectedItem = .builtInStream(.unread)

        library.markAllRead(in: .builtInStream(.unread))

        #expect(!context.hasChanges)
    }
}
