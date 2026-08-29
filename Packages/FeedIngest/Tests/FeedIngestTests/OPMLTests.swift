//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import FeedIngest

@Suite("OPML")
struct OPMLTests {

    @Test("Nested folders survive reading")
    func readsNestedFolders() throws {
        let document = try OPMLReader.read(try Fixture.data("subscriptions.opml"))

        #expect(document.title == "My Subscriptions")
        #expect(document.outlines.count == 2)

        let dev = try #require(document.outlines.first)
        #expect(dev.text == "Dev")
        #expect(dev.isFolder)
        #expect(dev.children.count == 2)

        let swift = try #require(dev.children.first)
        #expect(swift.text == "Swift")
        #expect(swift.isFolder)
        #expect(swift.children.count == 1)
    }

    @Test("Feeds are reported with the folder path they sit under")
    func flattensWithPaths() throws {
        let document = try OPMLReader.read(try Fixture.data("subscriptions.opml"))
        let feeds = document.feeds

        #expect(feeds.count == 3)

        // The path is what import turns back into nested folders, so a feed two
        // levels deep must report both levels.
        let sundell = try #require(feeds.first { $0.outline.text == "Swift by Sundell" })
        #expect(sundell.path == ["Dev", "Swift"])

        let fireball = try #require(feeds.first { $0.outline.text == "Daring Fireball" })
        #expect(fireball.path == ["Dev"])

        let root = try #require(feeds.first { $0.outline.text == "Root Level Feed" })
        #expect(root.path.isEmpty)
    }

    @Test("A document survives a write and read round trip")
    func roundTrips() throws {
        let original = try OPMLReader.read(try Fixture.data("subscriptions.opml"))

        let written = OPMLWriter.write(original)
        let reread = try OPMLReader.read(Data(written.utf8))

        // Getting out has to be as lossless as getting in, or the app is a
        // roach motel for subscription lists.
        #expect(reread == original)
    }

    // MARK: - Leaving another reader

    @Test("A Feedly export imports with its categories intact")
    func readsFeedlyExport() throws {
        // Moving in from Feedly is the likeliest way anyone arrives here, and
        // its export is the only file format that carries the whole
        // subscription list. Feedly writes OPML 1.0, puts both `text` and
        // `title` on every outline, and nests categories as parent outlines.
        let document = try OPMLReader.read(try Fixture.data("feedly-export.opml"))

        #expect(document.title == "Martin's Feedly Feeds")
        #expect(document.feeds.count == 5)
    }

    @Test("Feedly categories become folders, nesting and all")
    func mapsFeedlyCategories() throws {
        let document = try OPMLReader.read(try Fixture.data("feedly-export.opml"))
        let feeds = document.feeds

        let fireball = try #require(feeds.first { $0.outline.text == "Daring Fireball" })
        #expect(fireball.path == ["Design"])

        let sundell = try #require(feeds.first { $0.outline.text == "Swift by Sundell" })
        #expect(sundell.path == ["Dev", "Swift"])

        // A feed in no category has to land at the top level rather than being
        // dropped for having no folder to go in.
        let uncategorised = try #require(feeds.first { $0.outline.text == "Uncategorised Blog" })
        #expect(uncategorised.path.isEmpty)
    }

    @Test("A Feedly export can be exported straight back out")
    func feedlyExportRoundTrips() throws {
        let document = try OPMLReader.read(try Fixture.data("feedly-export.opml"))

        let reread = try OPMLReader.read(Data(OPMLWriter.write(document).utf8))

        // Arriving from Feedly must not be a one-way door.
        #expect(reread == document)
    }

    @Test("Ampersands in titles and URLs survive the round trip")
    func escapesCorrectly() throws {
        let document = OPMLDocument(
            title: "Feeds & Things",
            outlines: [
                OPMLOutline(
                    text: "News & <Opinion>",
                    xmlURL: URL(string: "https://example.com/feed?a=1&b=2")
                )
            ]
        )

        let reread = try OPMLReader.read(Data(OPMLWriter.write(document).utf8))
        #expect(reread == document)
    }
}
