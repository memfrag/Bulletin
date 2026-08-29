//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import FeedIngest

@Suite("Feed parsing")
struct FeedParserTests {

    // MARK: - Format detection

    @Test("Every supported format is detected from its own bytes",
          arguments: [
            ("rss.xml", FeedFormat.rss),
            ("atom.xml", FeedFormat.atom),
            ("jsonfeed.json", FeedFormat.json),
            ("rdf.xml", FeedFormat.rdf)
          ])
    func detectsFormat(fixture: String, expected: FeedFormat) throws {
        let detected = FeedFormat.detect(from: try Fixture.data(fixture))
        #expect(detected == expected)
    }

    @Test("An RDF feed is not mistaken for RSS")
    func rdfIsNotRSS() throws {
        // RSS 1.0 declares the namespace `http://purl.org/rss/1.0/`, so anything
        // matching loosely on "rss" gets this wrong and then fails to parse.
        let detected = FeedFormat.detect(from: try Fixture.data("rdf.xml"))
        #expect(detected == .rdf)
    }

    @Test("A document that is not a feed is rejected")
    func rejectsNonFeed() throws {
        let data = try Fixture.data("notafeed.txt")
        #expect(FeedFormat.detect(from: data) == nil)
        #expect(throws: FeedParsingError.unrecognizedFormat) {
            try FeedParser.parse(data)
        }
    }

    @Test("Malformed XML fails as malformed, not as unrecognized")
    func rejectsMalformed() throws {
        // It matters that this is distinguishable: unrecognized means "wrong
        // URL", malformed means "the publisher's feed is broken", and the Feed
        // Health view says different things about each.
        let data = try Fixture.data("malformed.xml")
        #expect(FeedFormat.detect(from: data) == .rss)
        #expect(throws: FeedParsingError.self) {
            try FeedParser.parse(data)
        }
    }

    // MARK: - RSS

    @Test("RSS: full content wins over the truncated description")
    func rssPrefersContentEncoded() throws {
        let feed = try FeedParser.parse(try Fixture.data("rss.xml"))

        #expect(feed.format == .rss)
        #expect(feed.title == "Example Blog")
        #expect(feed.homePageURL == URL(string: "https://example.com/"))
        #expect(feed.items.count == 2)

        let first = try #require(feed.items.first)
        #expect(first.guid == "tag:example.com,2026:post-1")
        #expect(first.contentHTML == "<p>The whole post, in all its glory.</p>")
        #expect(first.author == "ada@example.com")
        #expect(first.publishedAt != nil)
    }

    @Test("RSS: an item with no guid falls back to its link")
    func rssFallsBackToLink() throws {
        let feed = try FeedParser.parse(try Fixture.data("rss.xml"))
        let second = try #require(feed.items.last)

        // Dropping items for lacking a guid would silently lose articles from
        // every feed whose publisher never set one.
        #expect(second.guid == "https://example.com/posts/no-guid")
        #expect(second.author == "Grace Hopper")
    }

    // MARK: - Atom

    @Test("Atom: rel=self is not mistaken for the home page")
    func atomIgnoresSelfLink() throws {
        let feed = try FeedParser.parse(try Fixture.data("atom.xml"))

        #expect(feed.format == .atom)
        #expect(feed.title == "Example Atom Feed")
        // The self link points back at the feed; using it would make every
        // Atom feed's "open home page" go to XML.
        #expect(feed.homePageURL == URL(string: "https://atom.example.com/"))
    }

    @Test("Atom: an entry without published falls back to updated")
    func atomFallsBackToUpdated() throws {
        let feed = try FeedParser.parse(try Fixture.data("atom.xml"))
        let second = try #require(feed.items.last)

        #expect(second.title == "Atom Entry Without Published")
        #expect(second.publishedAt != nil)
        #expect(second.contentHTML == "Only a summary.")
    }

    // MARK: - JSON Feed

    @Test("JSON Feed: item author wins over feed author")
    func jsonPrefersItemAuthor() throws {
        let feed = try FeedParser.parse(try Fixture.data("jsonfeed.json"))

        #expect(feed.format == .json)
        #expect(feed.homePageURL == URL(string: "https://json.example.com/"))
        #expect(feed.items.first?.author == "Item Level Author")
        #expect(feed.items.last?.author == "Feed Level Author")
    }

    @Test("JSON Feed: content_text is used when there is no content_html")
    func jsonFallsBackToContentText() throws {
        let feed = try FeedParser.parse(try Fixture.data("jsonfeed.json"))
        #expect(feed.items.last?.contentHTML == "Plain text content.")
    }

    // MARK: - RDF

    @Test("RDF: items are found even though they are siblings of the channel")
    func rdfParsesSiblingItems() throws {
        let feed = try FeedParser.parse(try Fixture.data("rdf.xml"))

        #expect(feed.format == .rdf)
        #expect(feed.title == "Example RDF Feed")
        #expect(feed.homePageURL == URL(string: "https://rdf.example.com/"))
        // The structural trap of RSS 1.0: a parser that looks for items inside
        // <channel> finds none and reports an empty feed.
        #expect(feed.items.count == 2)
    }

    @Test("RDF: rdf:about is the item identity and dc: fields are read")
    func rdfReadsDublinCore() throws {
        let feed = try FeedParser.parse(try Fixture.data("rdf.xml"))
        let first = try #require(feed.items.first)

        #expect(first.guid == "https://rdf.example.com/one")
        #expect(first.title == "RDF Item One")
        #expect(first.author == "Barbara Liskov")
        #expect(first.publishedAt != nil)
        #expect(feed.items.last?.author == nil)
    }
}

// MARK: - Character references

@Suite("HTML entities")
struct HTMLEntityTests {

    @Test("Named references are decoded",
          arguments: [
            ("SwiftLee &raquo; Feed", "SwiftLee » Feed"),
            ("Tom &amp; Jerry", "Tom & Jerry"),
            ("She said &ldquo;no&rdquo;", "She said \u{201C}no\u{201D}"),
            ("Wait&hellip; what?", "Wait… what?"),
            ("A &mdash; B", "A — B"),
            ("&copy; 2026", "© 2026")
          ])
    func decodesNamed(input: String, expected: String) {
        // The first case is the one that shipped: a feed title lifted from a
        // WordPress `<link rel="alternate" title="...">` attribute.
        #expect(HTMLEntities.decode(input) == expected)
    }

    @Test("Numeric references are decoded, decimal and hexadecimal",
          arguments: [
            ("It&#8217;s here", "It\u{2019}s here"),
            ("It&#x2019;s here", "It\u{2019}s here"),
            ("&#65;&#66;&#67;", "ABC")
          ])
    func decodesNumeric(input: String, expected: String) {
        #expect(HTMLEntities.decode(input) == expected)
    }

    @Test("Text with no references is returned unchanged",
          arguments: ["Daring Fireball", "", "100% of the time", "a & b"])
    func leavesPlainTextAlone(input: String) {
        // A bare ampersand is not a reference and must survive.
        #expect(HTMLEntities.decode(input) == input)
    }

    @Test("An unknown reference is left visible rather than dropped")
    func preservesUnknownReferences() {
        // Deleting it would silently change the title; leaving it makes the gap
        // obvious if one ever matters.
        #expect(HTMLEntities.decode("A &notareal; B") == "A &notareal; B")
    }

    @Test("An unterminated reference does not eat the rest of the string")
    func handlesUnterminatedReference() {
        #expect(HTMLEntities.decode("Q&A without a semicolon") == "Q&A without a semicolon")
        #expect(HTMLEntities.decode("trailing &") == "trailing &")
    }

    @Test("Feed and item titles are decoded when parsed")
    func decodesParsedTitles() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>SwiftLee &amp;raquo; Feed</title>
          <link>https://example.com/</link>
          <item>
            <title>It&amp;#8217;s a title</title>
            <link>https://example.com/one</link>
            <author>Antoine &amp;amp; Co</author>
          </item>
        </channel></rss>
        """
        let feed = try FeedParser.parse(Data(xml.utf8))

        // The XML parser resolves &amp; to &, leaving the HTML reference behind
        // for this pass to finish.
        #expect(feed.title == "SwiftLee » Feed")
        #expect(feed.items.first?.title == "It\u{2019}s a title")
        #expect(feed.items.first?.author == "Antoine & Co")
    }
}
