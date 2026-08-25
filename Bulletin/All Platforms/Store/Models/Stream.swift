//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// A saved query, evaluated live every time it is viewed.
///
/// Streams store only the query, never a list of matches, so editing one takes
/// effect retroactively and instantly with no reprocessing pass.
///
/// - Important: Mirrored to CloudKit — see the note on ``Feed``.
///
@Model
final class Stream {

    var id: UUID = UUID()

    var name: String = ""

    /// The query in its text form, e.g. `unread folder:Dev -tag:noise after:7d`.
    ///
    /// Text is the canonical representation: the rule builder is a view onto it
    /// and round-trips through it losslessly.
    var queryText: String = ""

    var systemImage: String = "line.3.horizontal.decrease.circle"

    var sortIndex: Int = 0

    var createdAt: Date = Date()

    init(name: String, queryText: String, systemImage: String = "line.3.horizontal.decrease.circle") {
        self.id = UUID()
        self.name = name
        self.queryText = queryText
        self.systemImage = systemImage
        self.createdAt = Date()
    }
}
