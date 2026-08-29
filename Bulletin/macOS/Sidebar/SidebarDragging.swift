//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {

    /// A feed being dragged within the sidebar.
    ///
    /// A private type rather than plain text, so dragging a subscription into
    /// another app does not paste a bare identifier at somebody.
    nonisolated static let bulletinFeedReference =
        UTType(exportedAs: "pizza.martin.Bulletin.feed-reference")

    /// A folder being dragged within the sidebar.
    nonisolated static let bulletinFolderReference =
        UTType(exportedAs: "pizza.martin.Bulletin.folder-reference")
}

/// The identity of a dragged feed.
nonisolated struct FeedReference: Codable, Transferable {

    let feedID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bulletinFeedReference)
    }
}

/// The identity of a dragged folder.
nonisolated struct FolderReference: Codable, Transferable {

    let folderID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bulletinFolderReference)
    }
}
