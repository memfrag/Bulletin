//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import AppRouting

extension AppEnvironment {

    // MARK: - Live AppEnvironment

    /// Builds a live environment configured for production behavior.
    ///
    /// Intended only for ``#Preview`` usage and tests where an explicit instance is required.
    /// Most code should access ``shared`` instead.
    ///
    /// - Returns: A new ``AppEnvironment`` instance with live dependencies.
    ///
    internal static func live() -> AppEnvironment {
        AppEnvironment(
            appSettings: AppSettings(),
            modelContainer: makeModelContainer(),
            engineeringMode: EngineeringMode.shared
        )
    }

    /// Opens the on-disk stores.
    ///
    /// There is no meaningful way to run without them, and continuing with a
    /// half-built environment would only postpone the failure to somewhere less
    /// diagnosable, so this traps rather than papering over it.
    private static func makeModelContainer() -> ModelContainer {
        do {
            return try BulletinModelContainer.make()
        } catch {
            fatalError("Could not open the Bulletin stores: \(error)")
        }
    }
}
