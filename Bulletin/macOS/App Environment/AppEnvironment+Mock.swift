//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import AppRouting

extension AppEnvironment {

    // MARK: - Mock AppEnvironment

    #if DEBUG
    /// Builds a mock environment configured for development and preview usage.
    ///
    /// Available only in `DEBUG` builds.
    ///
    /// - Returns: A new ``AppEnvironment`` instance with mocked dependencies.
    ///
    internal static func mock() -> AppEnvironment {
        AppEnvironment(
            appSettings: AppSettings.mock(),
            modelContainer: (try? BulletinModelContainer.make(inMemory: true))
                ?? { fatalError("Could not open an in-memory store for previews.") }(),
            engineeringMode: EngineeringMode.shared
        )
    }
    #endif
}
