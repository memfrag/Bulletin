//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import FeedIngest

@Suite("Canonical URLs")
struct CanonicalURLTests {

    @Test("The same article from different feeds canonicalizes to one URL",
          arguments: [
            "https://example.com/posts/one?utm_source=rss&utm_medium=feed",
            "http://www.example.com/posts/one/",
            "https://example.com/posts/one#section-2",
            "https://EXAMPLE.com:443/posts/one",
            "https://example.com/posts/one?fbclid=abc123"
          ])
    func collapsesToSameURL(variant: String) throws {
        let expected = URL(string: "https://example.com/posts/one")
        let canonical = CanonicalURL.canonicalize(try #require(URL(string: variant)))
        #expect(canonical == expected)
    }

    @Test("Parameters that select content are preserved")
    func preservesMeaningfulParameters() throws {
        // Stripping these would merge genuinely different articles, which hides
        // something the user wanted to read. Showing a duplicate is the far
        // cheaper mistake.
        let url = try #require(URL(string: "https://example.com/article?id=42&page=2&utm_source=rss"))
        let canonical = CanonicalURL.canonicalize(url)
        #expect(canonical == URL(string: "https://example.com/article?id=42&page=2"))
    }

    @Test("The root path keeps its slash")
    func keepsRootSlash() throws {
        let url = try #require(URL(string: "https://example.com/"))
        #expect(CanonicalURL.canonicalize(url) == URL(string: "https://example.com/"))
    }

    @Test("Different articles stay different")
    func doesNotOverMerge() throws {
        let one = CanonicalURL.canonicalize(try #require(URL(string: "https://example.com/posts/one")))
        let two = CanonicalURL.canonicalize(try #require(URL(string: "https://example.com/posts/two")))
        #expect(one != two)
    }
}
