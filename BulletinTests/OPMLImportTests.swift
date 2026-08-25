//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
import FeedIngest
@testable import Bulletin

@MainActor
@Suite("OPML import and export", .serialized)
struct OPMLImportTests {

    @Test("Importing recreates the nested folder hierarchy")
    func importCreatesNestedFolders() throws {
        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context)

        let result = try store.importOPML(SampleFeed.opml)

        #expect(result.importedFeedCount == 3)
        #expect(result.createdFolderCount == 2)

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let dev = try #require(folders.first { $0.name == "Dev" })
        let swift = try #require(folders.first { $0.name == "Swift" })

        #expect(dev.parent == nil)
        #expect(swift.parent?.id == dev.id)
        #expect(swift.path == ["Dev", "Swift"])
    }

    @Test("Feeds land in the folder their outline sat in")
    func importPlacesFeedsCorrectly() throws {
        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context)
        try store.importOPML(SampleFeed.opml)

        let feeds = try context.fetch(FetchDescriptor<Feed>())

        let sundell = try #require(feeds.first { $0.title == "Swift by Sundell" })
        #expect(sundell.folder?.name == "Swift")
        #expect(sundell.folder?.path == ["Dev", "Swift"])

        let fireball = try #require(feeds.first { $0.title == "Daring Fireball" })
        #expect(fireball.folder?.name == "Dev")

        let root = try #require(feeds.first { $0.title == "Root Level Feed" })
        #expect(root.folder == nil)
    }

    @Test("A folder reports the feeds nested beneath it")
    func folderCollectsDescendantFeeds() throws {
        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context)
        try store.importOPML(SampleFeed.opml)

        let folders = try context.fetch(FetchDescriptor<Folder>())
        let dev = try #require(folders.first { $0.name == "Dev" })

        // This is what makes `folder:Dev` match descendants rather than only
        // direct children.
        #expect(dev.feeds?.count == 1)
        #expect(dev.feedsIncludingDescendants.count == 2)
    }

    @Test("Importing the same file twice adds nothing")
    func importIsIdempotent() throws {
        let context = try TestStore.makeContext()
        let store = FeedStore(modelContext: context)

        try store.importOPML(SampleFeed.opml)
        let second = try store.importOPML(SampleFeed.opml)

        // Re-importing after a partial failure is the obvious thing to try, so
        // it must not duplicate every subscription.
        #expect(second.importedFeedCount == 0)
        #expect(second.alreadySubscribedCount == 3)
        #expect(second.createdFolderCount == 0)
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 3)
        #expect(try context.fetch(FetchDescriptor<Folder>()).count == 2)
    }

    @Test("Exporting and re-importing preserves the whole subscription list")
    func exportRoundTrips() throws {
        let sourceContext = try TestStore.makeContext()
        let sourceStore = FeedStore(modelContext: sourceContext)
        try sourceStore.importOPML(SampleFeed.opml)

        let exported = try sourceStore.exportOPML()

        // A reader you cannot leave is a reader you should not enter.
        let destinationContext = try TestStore.makeContext()
        let destinationStore = FeedStore(modelContext: destinationContext)
        let result = try destinationStore.importOPML(Data(exported.utf8))

        #expect(result.importedFeedCount == 3)
        #expect(result.createdFolderCount == 2)

        let feeds = try destinationContext.fetch(FetchDescriptor<Feed>())
        let sundell = try #require(feeds.first { $0.title == "Swift by Sundell" })
        #expect(sundell.folder?.path == ["Dev", "Swift"])
    }
}
