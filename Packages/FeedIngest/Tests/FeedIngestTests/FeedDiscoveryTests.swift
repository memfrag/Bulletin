//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import FeedIngest

@Suite("Feed discovery")
struct FeedDiscoveryTests {

    @Test("Every advertised feed in the head is found, in document order")
    func findsFeedLinks() throws {
        let html = try Fixture.string("discovery.html")
        let base = try #require(URL(string: "https://site.example.com/blog/"))

        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: base)

        #expect(feeds.count == 3)
        #expect(feeds.map(\.format) == [.rss, .atom, .json])
        #expect(feeds.first?.title == "Main Feed")
    }

    @Test("Relative hrefs resolve against the page they came from")
    func resolvesRelativeHrefs() throws {
        let html = try Fixture.string("discovery.html")
        let base = try #require(URL(string: "https://site.example.com/blog/"))

        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: base)
        #expect(feeds.first?.url == URL(string: "https://site.example.com/feed.xml"))
    }

    @Test("Entities in hrefs are decoded")
    func decodesEntities() throws {
        let html = try Fixture.string("discovery.html")
        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: nil)

        let comments = try #require(feeds.first { $0.format == .atom })
        #expect(comments.title == "Comments & Replies")
    }

    @Test("Non-feed alternates and links outside the head are ignored")
    func ignoresIrrelevantLinks() throws {
        let html = try Fixture.string("discovery.html")
        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: nil)

        // `rel="alternate" type="text/html"` is a print stylesheet or a
        // translation, not a feed. And a page body can contain anything at all.
        #expect(!feeds.contains { $0.url.absoluteString.contains("print") })
        #expect(!feeds.contains { $0.url.absoluteString.contains("should-be-ignored") })
    }
}
