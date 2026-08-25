//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// A user-applied label on an article.
///
/// Tags are many-to-many and apply to articles only — organising *feeds* is
/// what the folder tree is for. Nothing applies a tag automatically; streams
/// are live queries and never mutate what they match.
///
/// - Important: Mirrored to CloudKit — see the note on ``Feed``.
///
@Model
final class Tag {

    var id: UUID = UUID()

    var name: String = ""

    var statuses: [ArticleStatus]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}
