//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import FeedIngest

extension FeedStore {

    /// The result of importing a subscription list.
    struct OPMLImportResult: Sendable, Equatable {
        var importedFeedCount: Int = 0
        var alreadySubscribedCount: Int = 0
        var createdFolderCount: Int = 0
    }

    /// Imports an OPML subscription list, recreating its folder hierarchy.
    ///
    /// Feeds already subscribed are counted and skipped rather than duplicated,
    /// so importing the same file twice is harmless — which matters, because
    /// re-importing after a partial failure is the obvious thing to try.
    @discardableResult
    func importOPML(_ data: Data) throws -> OPMLImportResult {

        let document = try OPMLReader.read(data)
        var result = OPMLImportResult()

        for entry in document.feeds {
            guard let feedURL = entry.outline.xmlURL else { continue }

            if try feed(withURL: feedURL) != nil {
                result.alreadySubscribedCount += 1
                continue
            }

            let folder = try folder(atPath: entry.path, createdCount: &result.createdFolderCount)

            let feed = Feed(
                feedURL: feedURL,
                title: entry.outline.text,
                homePageURL: entry.outline.htmlURL
            )
            feed.folder = folder
            modelContext.insert(feed)
            result.importedFeedCount += 1
        }

        try modelContext.save()
        return result
    }

    /// Exports every subscription, preserving the folder tree.
    func exportOPML(title: String = "Bulletin Subscriptions") throws -> String {
        let rootFolders = try modelContext.fetch(
            FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil })
        ).sorted { $0.sortIndex < $1.sortIndex }

        let rootFeeds = try modelContext.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.folder == nil })
        )

        let outlines = rootFolders.map(Self.outline(for:)) + rootFeeds.map(Self.outline(for:))
        return OPMLWriter.write(OPMLDocument(title: title, outlines: outlines))
    }

    // MARK: - Folders

    /// Finds or creates the folder at a path, creating intermediate levels.
    private func folder(atPath path: [String], createdCount: inout Int) throws -> Folder? {

        var parent: Folder?

        for name in path {
            let siblings = try modelContext.fetch(
                FetchDescriptor<Folder>(predicate: #Predicate { $0.name == name })
            )
            // Names are only unique among siblings, so match on the parent too.
            if let existing = siblings.first(where: { $0.parent?.id == parent?.id }) {
                parent = existing
                continue
            }

            let folder = Folder(name: name, parent: parent)
            modelContext.insert(folder)
            createdCount += 1
            parent = folder
        }

        return parent
    }

    // MARK: - Outlines

    private static func outline(for folder: Folder) -> OPMLOutline {
        let children = (folder.children ?? []).sorted { $0.sortIndex < $1.sortIndex }.map(outline(for:))
            + (folder.feeds ?? []).map(outline(for:))
        return OPMLOutline(text: folder.name, children: children)
    }

    private static func outline(for feed: Feed) -> OPMLOutline {
        OPMLOutline(
            text: feed.displayTitle,
            xmlURL: feed.feedURL,
            htmlURL: feed.homePageURL
        )
    }
}
