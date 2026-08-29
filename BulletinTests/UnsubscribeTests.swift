//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// Deleting a feed has to take everything it brought with it.
///
/// SwiftData's cascade reaches the articles and their status. It does not reach
/// what is keyed by id rather than by relationship — extracted bodies, fetch
/// bookkeeping, and the search index — and orphans there are invisible: the
/// bodies are the heaviest data in the store, and stale index rows go on
/// returning articles that no longer exist.
@MainActor
@Suite("Unsubscribing", .serialized)
struct UnsubscribeTests {

    private func seed(_ context: ModelContext) throws -> (kept: Feed, doomed: Feed) {
        let kept = Feed(feedURL: URL(string: "https://kept.example.com/feed")!, title: "Kept")
        let doomed = Feed(feedURL: URL(string: "https://doomed.example.com/feed")!, title: "Doomed")
        context.insert(kept)
        context.insert(doomed)

        for (index, feed) in [kept, doomed, doomed].enumerated() {
            let article = Article(guid: "g\(index)", feed: feed, title: "Article \(index)")
            article.url = URL(string: "https://example.com/\(index)")
            let status = ArticleStatus(article: article)
            status.isBookmarked = true
            context.insert(article)
            context.insert(status)
            article.status = status

            context.insert(ArticleBody(
                articleID: article.id,
                source: .nativeExtraction,
                contentHTML: "<p>body \(index)</p>",
                plainText: "body \(index)"
            ))
        }

        context.insert(FeedFetchState(feedID: kept.id))
        context.insert(FeedFetchState(feedID: doomed.id))

        try context.save()
        return (kept, doomed)
    }

    @Test("The feed's articles and their status go with it")
    func deletesArticles() throws {
        let context = try TestStore.makeContext()
        let (kept, doomed) = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.unsubscribe(doomed)

        let remaining = try context.fetch(FetchDescriptor<Article>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.feedID == kept.id)
        #expect(try context.fetch(FetchDescriptor<ArticleStatus>()).count == 1)
    }

    @Test("The extracted bodies go too, rather than being orphaned")
    func deletesBodies() throws {
        let context = try TestStore.makeContext()
        let (_, doomed) = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.unsubscribe(doomed)

        // Bodies live in the local store and are keyed by article id, so no
        // cascade reaches them. They are also the largest thing in the store,
        // which makes leaking them the expensive mistake.
        let bodies = try context.fetch(FetchDescriptor<ArticleBody>())
        #expect(bodies.count == 1)
    }

    @Test("The feed's fetch bookkeeping goes too")
    func deletesFetchState() throws {
        let context = try TestStore.makeContext()
        let (kept, doomed) = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.unsubscribe(doomed)

        let states = try context.fetch(FetchDescriptor<FeedFetchState>())
        #expect(states.count == 1)
        #expect(states.first?.feedID == kept.id)
    }

    @Test("Other feeds are untouched")
    func leavesOtherFeedsAlone() throws {
        let context = try TestStore.makeContext()
        let (kept, doomed) = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.unsubscribe(doomed)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        #expect(feeds.count == 1)
        #expect(feeds.first?.id == kept.id)
    }

    @Test("Selecting the deleted feed does not leave the sidebar on a dead id")
    func resetsSelection() throws {
        let context = try TestStore.makeContext()
        let (_, doomed) = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)
        library.selectedItem = .feed(doomed.id)

        library.unsubscribe(doomed)

        // Otherwise the article list stays titled after a feed that is gone.
        #expect(library.selectedItem == .builtInStream(.unread))
        #expect(library.selectedArticleID == nil)
    }

    @Test("Deleting a feed you were not looking at leaves the selection alone")
    func keepsUnrelatedSelection() throws {
        let context = try TestStore.makeContext()
        let (kept, doomed) = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)
        library.selectedItem = .feed(kept.id)

        library.unsubscribe(doomed)

        #expect(library.selectedItem == .feed(kept.id))
    }

    @Test("Its rows leave the search index rather than lingering")
    func removesFromSearchIndex() throws {
        let context = try TestStore.makeContext()
        let (_, doomed) = try seed(context)
        let index = try SearchIndex(url: nil)
        let indexer = ArticleIndexer(modelContext: context, index: index)

        let doomedIDs = (doomed.articles ?? []).map(\.id)
        indexer.rebuild()
        #expect(index.count == 3)

        indexer.remove(ids: doomedIDs)

        // A stale row here means search and every stream keep returning an
        // article that no longer exists, which resolves to nothing.
        #expect(index.count == 1)
    }
}
