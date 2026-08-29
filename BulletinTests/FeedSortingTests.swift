//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// The sidebar is a list people scan for a name, so it has to be in the order
/// they would look for it.
@MainActor
@Suite("Feed sorting", .serialized)
struct FeedSortingTests {

    private func feeds(_ titles: [String], in context: ModelContext) -> [Feed] {
        titles.map { title in
            let feed = Feed(feedURL: URL(string: "https://example.com/\(title.hashValue)")!, title: title)
            context.insert(feed)
            return feed
        }
    }

    @Test("A lowercase name is not exiled to the end of the list")
    func sortsCaseInsensitively() throws {
        let context = try TestStore.makeContext()
        let all = feeds(["SwiftLee", "iOS Dev Weekly", "Artem Novichkov", "Nil Coalescing"], in: context)

        let sorted = all.sortedByTitle.map(\.displayTitle)

        // Comparing with `<` puts every capitalised name first, so `iOS Dev
        // Weekly` ended up after `SwiftLee` instead of near the top.
        #expect(sorted == ["Artem Novichkov", "iOS Dev Weekly", "Nil Coalescing", "SwiftLee"])
    }

    @Test("Numbers order the way people read them")
    func sortsNumericallyAware() throws {
        let context = try TestStore.makeContext()
        let all = feeds(["Issue 10", "Issue 9", "Issue 100"], in: context)

        // Plain string ordering gives 10, 100, 9.
        #expect(all.sortedByTitle.map(\.displayTitle) == ["Issue 9", "Issue 10", "Issue 100"])
    }

    @Test("A renamed feed sorts under the name it now shows")
    func sortsByDisplayTitle() throws {
        let context = try TestStore.makeContext()
        let all = feeds(["Zebra Blog", "Apple Blog"], in: context)
        all[0].customTitle = "Aardvark"

        // Root feeds used to be ordered by the stored title while the sidebar
        // displayed something else, so a renamed feed sat under its old name.
        #expect(all.sortedByTitle.map(\.displayTitle) == ["Aardvark", "Apple Blog"])
    }

    @Test("Accented names sort where the alphabet puts them")
    func sortsDiacritics() throws {
        let context = try TestStore.makeContext()
        let all = feeds(["Zed", "Ölands Nyheter", "Apple"], in: context)

        let sorted = all.sortedByTitle.map(\.displayTitle)
        #expect(sorted.first == "Apple")
        #expect(sorted.last == "Zed")
    }

    @Test("An untitled feed falls back to its host and still sorts")
    func sortsUntitledFeeds() throws {
        let context = try TestStore.makeContext()
        let named = feeds(["Zebra"], in: context)
        let untitled = Feed(feedURL: URL(string: "https://alpha.example.com/feed")!)
        context.insert(untitled)

        let sorted = (named + [untitled]).sortedByTitle.map(\.displayTitle)
        #expect(sorted == ["alpha.example.com", "Zebra"])
    }
}
