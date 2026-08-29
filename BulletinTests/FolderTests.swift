//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// Folders were modelled from the start but only ever created by importing
/// OPML. These cover the operations the sidebar now performs directly.
@MainActor
@Suite("Folders", .serialized)
struct FolderTests {

    private func makeFeed(_ title: String, in context: ModelContext) -> Feed {
        let feed = Feed(feedURL: URL(string: "https://example.com/\(title.hashValue)")!, title: title)
        context.insert(feed)
        return feed
    }

    // MARK: - Moving feeds

    @Test("A feed moves into a folder and back out")
    func movesFeedBetweenFolders() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let feed = makeFeed("Example", in: context)
        let dev = library.createFolder(named: "Dev")

        library.move(feed, to: dev)
        #expect(feed.folder?.id == dev.id)
        #expect(dev.feeds?.count == 1)

        library.move(feed, to: nil)
        #expect(feed.folder == nil)
        #expect(dev.feeds?.isEmpty == true)
    }

    @Test("Moving a feed to where it already is changes nothing")
    func moveIsIdempotent() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let feed = makeFeed("Example", in: context)
        let dev = library.createFolder(named: "Dev")

        library.move(feed, to: dev)
        library.move(feed, to: dev)

        #expect(dev.feeds?.count == 1)
    }

    // MARK: - Nesting

    @Test("Folders nest, and a folder query reaches its descendants")
    func nestsFolders() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")
        let swift = library.createFolder(named: "Swift", parent: dev)
        let feed = makeFeed("Deep", in: context)
        library.move(feed, to: swift)

        #expect(swift.path == ["Dev", "Swift"])
        // `folder:Dev` matches descendants, so the nested feed has to be found.
        #expect(dev.feedsIncludingDescendants.count == 1)
        #expect(dev.feeds?.isEmpty == true)
    }

    @Test("A folder cannot be dropped inside itself")
    func refusesSelfNesting() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")

        #expect(library.move(dev, into: dev) == false)
        #expect(dev.parent == nil)
    }

    @Test("A folder cannot be dropped inside its own descendant")
    func refusesCycles() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")
        let swift = library.createFolder(named: "Swift", parent: dev)

        // Allowing this would detach Dev and Swift from the tree entirely:
        // each would be inside the other and neither reachable from the root.
        #expect(library.move(dev, into: swift) == false)
        #expect(dev.parent == nil)
        #expect(swift.parent?.id == dev.id)
    }

    @Test("A folder can be moved back out to the top level")
    func movesFolderToRoot() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")
        let swift = library.createFolder(named: "Swift", parent: dev)

        #expect(library.move(swift, into: nil))
        #expect(swift.parent == nil)
    }

    // MARK: - Deleting

    @Test("Deleting a folder keeps its feeds, moving them to the top level")
    func deletingFolderKeepsFeeds() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")
        let feed = makeFeed("Example", in: context)
        library.move(feed, to: dev)

        library.deleteFolder(dev)

        // Losing a subscription because a folder was tidied away would be a
        // nasty surprise.
        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
        #expect(feed.folder == nil)
        #expect(try context.fetch(FetchDescriptor<Folder>()).isEmpty)
    }

    @Test("Deleting a folder keeps feeds nested deep inside it")
    func deletingFolderKeepsNestedFeeds() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")
        let swift = library.createFolder(named: "Swift", parent: dev)
        let feed = makeFeed("Deep", in: context)
        library.move(feed, to: swift)

        library.deleteFolder(dev)

        #expect(try context.fetch(FetchDescriptor<Feed>()).count == 1)
        #expect(feed.folder == nil)
    }

    @Test("Deleting the selected folder moves the selection somewhere real")
    func deletingSelectedFolderResetsSelection() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let dev = library.createFolder(named: "Dev")
        library.selectedItem = .folder(dev.id)

        library.deleteFolder(dev)

        #expect(library.selectedItem == .builtInStream(.unread))
    }

    // MARK: - Naming

    @Test("A folder created with no name still has one")
    func namesUntitledFolders() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)

        let folder = library.createFolder(named: "   ")

        #expect(folder.name == "New Folder")
    }

    @Test("Renaming trims, and refuses to leave a folder nameless")
    func renamesFolders() throws {
        let context = try TestStore.makeContext()
        let library = Library(modelContext: context, indexURL: nil)
        let folder = library.createFolder(named: "Dev")

        library.renameFolder(folder, to: "  Development  ")
        #expect(folder.name == "Development")

        library.renameFolder(folder, to: "   ")
        #expect(folder.name == "Development")
    }
}
