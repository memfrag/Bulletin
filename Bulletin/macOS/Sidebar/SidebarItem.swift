//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A selectable row in the sidebar.
///
/// The sidebar leads with streams — saved queries evaluated live against the
/// article store — and demotes the subscription tree to a section beneath them.
/// Folders nest arbitrarily and a `folder` selection matches its descendants.
///
enum SidebarItem: Hashable {

    // MARK: Streams

    /// One of the streams that always exists.
    case builtInStream(BuiltInStream)

    /// A user-defined saved query.
    case stream(UUID)

    // MARK: Subscriptions

    /// A folder in the subscription tree, matching its descendants.
    case folder(UUID)

    /// A single feed.
    case feed(UUID)
}

// MARK: - Protocol Conformances

extension SidebarItem: Identifiable {
    var id: Self { self }
}
