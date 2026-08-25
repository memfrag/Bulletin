//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// A node in the subscription tree.
///
/// Folders nest arbitrarily, matching OPML's real structure, so importing and
/// exporting a subscription list is lossless. A `folder:` query term matches a
/// folder and all of its descendants.
///
/// - Important: Mirrored to CloudKit — see the note on ``Feed``.
///
@Model
final class Folder {

    var id: UUID = UUID()

    var name: String = ""

    /// Position among its siblings.
    var sortIndex: Int = 0

    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder]? = []

    @Relationship(deleteRule: .nullify, inverse: \Feed.folder)
    var feeds: [Feed]? = []

    init(name: String, parent: Folder? = nil, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.parent = parent
        self.sortIndex = sortIndex
    }
}

// MARK: - Convenience

extension Folder {

    /// The folder's path from the root, e.g. `["Dev", "Swift"]`.
    ///
    /// Used as a query facet so that `folder:Dev` can match descendants without
    /// walking the tree at query time.
    var path: [String] {
        var components: [String] = []
        var node: Folder? = self
        var guardCount = 0
        while let current = node, guardCount < 64 {
            components.insert(current.name, at: 0)
            node = current.parent
            guardCount += 1
        }
        return components
    }

    /// Every feed in this folder and all folders beneath it.
    var feedsIncludingDescendants: [Feed] {
        (feeds ?? []) + (children ?? []).flatMap(\.feedsIncludingDescendants)
    }
}
