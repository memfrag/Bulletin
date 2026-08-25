//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import ContentExtraction

/// Measured against a corpus of saved pages, so that changing a heuristic is a
/// measurable act rather than a hopeful one.
@Suite("Heuristic extraction")
struct HeuristicExtractorTests {

    private let baseURL = URL(string: "https://example.com/posts/one")!

    // MARK: - Semantic markup

    @Test("A page with an <article> element yields its contents")
    func extractsSemanticArticle() throws {
        let article = try HeuristicExtractor.extract(
            html: try Fixture.html("semantic-article.html"),
            baseURL: baseURL
        )

        #expect(article.title == "How Feeds Got Truncated")
        #expect(article.byline == "Ada Lovelace")
        #expect(article.plainText.contains("Publishers discovered"))
        #expect(article.isSubstantial)
    }

    @Test("Navigation, sidebars and footers are left behind")
    func stripsChrome() throws {
        let article = try HeuristicExtractor.extract(
            html: try Fixture.html("semantic-article.html"),
            baseURL: baseURL
        )

        // Anything that survives here shows up in the reader as the site's
        // furniture pasted into the middle of the article.
        #expect(!article.plainText.contains("Archive"))
        #expect(!article.plainText.contains("Related one"))
        #expect(!article.plainText.contains("Copyright the example"))
        #expect(!article.plainText.contains("The Example Times"))
    }

    @Test("Relative image and link URLs are made absolute")
    func resolvesRelativeURLs() throws {
        let article = try HeuristicExtractor.extract(
            html: try Fixture.html("semantic-article.html"),
            baseURL: baseURL
        )

        // The reader renders this markup under a different base, so a relative
        // src resolves to nothing and the image silently disappears.
        #expect(article.contentHTML.contains("https://example.com/images/chart.png"))
        #expect(!article.contentHTML.contains("\"/images/chart.png\""))
    }

    // MARK: - Scoring

    @Test("A page of unmarked divs still yields the text, not the sidebar")
    func scoresDivSoup() throws {
        let article = try HeuristicExtractor.extract(
            html: try Fixture.html("div-soup.html"),
            baseURL: baseURL
        )

        #expect(article.plainText.contains("never heard of the article element"))
        // The rail next door is nothing but links, and losing to it is the
        // classic failure of a naive "biggest element wins" extractor.
        #expect(!article.plainText.contains("Popular six"))
    }

    @Test("A page that is only links yields no article")
    func rejectsLinkFarm() throws {
        // An index page is not an article. Returning its link list as one would
        // be worse than admitting defeat and offering the live page.
        #expect(throws: ContentExtractionError.noArticleFound) {
            try HeuristicExtractor.extract(
                html: try Fixture.html("link-farm.html"),
                baseURL: baseURL
            )
        }
    }

    @Test("A paywall stub is not mistaken for an article")
    func rejectsTinyContent() throws {
        #expect(throws: ContentExtractionError.noArticleFound) {
            try HeuristicExtractor.extract(
                html: try Fixture.html("tiny.html"),
                baseURL: baseURL
            )
        }
    }

    @Test("Substantiality is judged on text length")
    func judgesSubstantiality() {
        let scrap = ExtractedArticle(title: nil, byline: nil, contentHTML: "", plainText: "Too short.")
        #expect(!scrap.isSubstantial)

        let real = ExtractedArticle(
            title: nil,
            byline: nil,
            contentHTML: "",
            plainText: String(repeating: "word ", count: 100)
        )
        #expect(real.isSubstantial)
    }
}

// MARK: - Encoding

@Suite("Page fetching")
struct PageFetcherTests {

    @Test("A page declaring a legacy encoding is decoded with it")
    func decodesDeclaredEncoding() throws {
        // Reading windows-1252 as UTF-8 turns every curly apostrophe into a
        // replacement character, which is very visible and very ugly.
        let text = "Don\u{2019}t"
        let data = try #require(text.data(using: .windowsCP1252))
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=windows-1252"]
            )
        )

        #expect(PageFetcher.decode(data, response: response) == text)
    }
}
