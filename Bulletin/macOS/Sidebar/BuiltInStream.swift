//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The streams that ship with the app and always exist.
///
/// Built-in streams are ordinary saved queries (see `Stream`), they are simply
/// ones the user cannot delete. They are listed above user-defined streams in
/// the sidebar.
///
enum BuiltInStream: String, CaseIterable {

    case unread
    case today
    case bookmarked

    var title: String {
        switch self {
        case .unread: String(localized: "Unread")
        case .today: String(localized: "Today")
        case .bookmarked: String(localized: "Bookmarked")
        }
    }

    var systemImage: String {
        switch self {
        case .unread: "circle.inset.filled"
        case .today: "sun.horizon"
        case .bookmarked: "bookmark"
        }
    }
}

// MARK: - Protocol Conformances

extension BuiltInStream: Identifiable {
    var id: Self { self }
}
