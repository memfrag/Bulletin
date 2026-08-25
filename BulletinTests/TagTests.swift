//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// - Note: The model is referred to as `Bulletin.Tag` throughout, because
///   Swift Testing has a `Tag` of its own and the bare name is ambiguous here.
@MainActor
@Suite("Tags", .serialized)
struct TagTests {

    private func seed(_ context: ModelContext) throws -> [Article] {
        let feed = Feed(feedURL: URL(string: "https://example.com/feed")!, title: "Example")
        context.insert(feed)

        var articles: [Article] = []
        for index in 0..<2 {
            let article = Article(guid: "g\(index)", feed: feed, title: "Article \(index)")
            let status = ArticleStatus(article: article)
            context.insert(article)
            context.insert(status)
            article.status = status
            articles.append(article)
        }
        try context.save()
        return articles
    }

    @Test("Applying a tag creates it once and reuses it after")
    func reusesExistingTags() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.addTag(named: "swift", to: articles[0])
        library.addTag(named: "swift", to: articles[1])

        #expect(try context.fetch(FetchDescriptor<Bulletin.Tag>()).count == 1)
        #expect(library.tags(on: articles[0]).map(\.name) == ["swift"])
        #expect(library.tags(on: articles[1]).map(\.name) == ["swift"])
    }

    @Test("Tag names are matched without regard to case")
    func matchesCaseInsensitively() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.addTag(named: "Swift", to: articles[0])
        library.addTag(named: "swift", to: articles[1])

        // Two tags that look identical in the sidebar and match different
        // articles is the worst possible outcome here.
        #expect(try context.fetch(FetchDescriptor<Bulletin.Tag>()).count == 1)
    }

    @Test("Applying the same tag twice does nothing the second time")
    func applyingTwiceIsIdempotent() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.addTag(named: "swift", to: articles[0])
        library.addTag(named: "swift", to: articles[0])

        #expect(library.tags(on: articles[0]).count == 1)
    }

    @Test("Removing a tag leaves it on other articles")
    func removalIsPerArticle() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)
        library.addTag(named: "swift", to: articles[0])
        library.addTag(named: "swift", to: articles[1])

        let tag = try #require(library.tags(on: articles[0]).first)
        library.removeTag(tag, from: articles[0])

        #expect(library.tags(on: articles[0]).isEmpty)
        #expect(library.tags(on: articles[1]).count == 1)
    }

    @Test("Blank tag names are refused")
    func refusesBlankNames() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)

        library.addTag(named: "   ", to: articles[0])

        #expect(try context.fetch(FetchDescriptor<Bulletin.Tag>()).isEmpty)
    }

    @Test("Pruning removes tags nothing uses any more")
    func prunesUnusedTags() throws {
        let context = try TestStore.makeContext()
        let articles = try seed(context)
        let library = Library(modelContext: context, indexURL: nil)
        library.addTag(named: "swift", to: articles[0])
        library.addTag(named: "keep", to: articles[1])

        let tag = try #require(library.tags(on: articles[0]).first)
        library.removeTag(tag, from: articles[0])
        library.pruneUnusedTags()

        // A tag list that only ever grows fills up with things removed from the
        // last article that had them.
        #expect(library.allTags.map(\.name) == ["keep"])
    }
}
