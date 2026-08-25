//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

public struct HelpWindow: Scene {

    public static let windowID = "help"

    public var body: some Scene {
        Window(Text("Bulletin Help", comment: "Help window title"), id: Self.windowID) {
            HelpView()
        }
        .commandsRemoved() // Don't show window in Windows menu
        .defaultPosition(.center)
        .defaultSize(width: 640, height: 520)
        .windowResizability(.contentMinSize)
    }
}
