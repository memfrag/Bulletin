//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// Pins down what `#Predicate` can actually express against this schema.
///
/// The article list is built out of these shapes, and SwiftData's predicate
/// support for optional to-one relationships is the kind of thing that compiles
/// and then returns the wrong rows, so each one is checked against real data
/// rather than assumed.
@MainActor
@Suite("Predicate support", .serialized)
struct PredicateProbeTests {

    private func seed(_ context: ModelContext) throws -> (feedA: Feed, feedB: Feed) {
        let feedA = Feed(feedURL: URL(string: "https://a.example.com/feed")!, title: "A")
        let feedB = Feed(feedURL: URL(string: "https://b.example.com/feed")!, title: "B")
        context.insert(feedA)
        context.insert(feedB)

        for (index, feed) in [feedA, feedA, feedB].enumerated() {
            let article = Article(guid: "g\(index)", feed: feed, title: "Article \(index)")
            article.publishedAt = Date(timeIntervalSince1970: TimeInterval(1_000_000 + index))
            let status = ArticleStatus(article: article)
            status.isRead = (index == 0)
            status.isStarred = (index == 2)
            context.insert(article)
            context.insert(status)
            article.status = status
        }
        try context.save()
        return (feedA, feedB)
    }

    @Test("Filtering by the denormalized feed id works")
    func filtersByFeedID() throws {
        let context = try TestStore.makeContext()
        let (feedA, _) = try seed(context)
        let id = feedA.id

        let articles = try context.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == id })
        )
        #expect(articles.count == 2)
    }

    @Test("Filtering by a set of feed ids works, which is how folders are queried")
    func filtersByFeedIDSet() throws {
        let context = try TestStore.makeContext()
        let (feedA, feedB) = try seed(context)
        let ids = [feedA.id, feedB.id]

        let articles = try context.fetch(
            FetchDescriptor<Article>(
                predicate: #Predicate { article in
                    if let feedID = article.feedID {
                        return ids.contains(feedID)
                    } else {
                        return false
                    }
                }
            )
        )
        #expect(articles.count == 3)
    }

    @Test("Filtering through the status relationship returns the right rows")
    func filtersThroughStatusRelationship() throws {
        let context = try TestStore.makeContext()
        _ = try seed(context)

        let unread = try context.fetch(
            FetchDescriptor<Article>(
                predicate: #Predicate { article in
                    article.status?.isRead == false
                }
            )
        )
        #expect(unread.count == 2)

        let starred = try context.fetch(
            FetchDescriptor<Article>(
                predicate: #Predicate { article in
                    article.status?.isStarred == true
                }
            )
        )
        #expect(starred.count == 1)
    }

    @Test("Sorting by published date descending works")
    func sortsByDate() throws {
        let context = try TestStore.makeContext()
        _ = try seed(context)

        var descriptor = FetchDescriptor<Article>()
        descriptor.sortBy = [SortDescriptor(\.publishedAt, order: .reverse)]
        let articles = try context.fetch(descriptor)

        #expect(articles.first?.title == "Article 2")
        #expect(articles.last?.title == "Article 0")
    }
}
