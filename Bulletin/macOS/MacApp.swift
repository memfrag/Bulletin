//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import AttributionsUI
import AppDesign
import Sparkle

@main
struct MacApp: App {
    
    // swiftlint:disable:next weak_delegate
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    
    init() {
        AppDesign.apply()
    }
    
    var body: some Scene {
        MainWindow(updater: updaterController.updater)
        MenuBarWindow()
        SettingsWindow()
        AboutWindow(developedBy: "Martin Johannesson",
                    attributionsWindowID: AttributionsWindow.windowID)
        AttributionsWindow([
            ("CGMath", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("MathKit", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al.")),
            ("FeedKit", .mit(year: "2016-2026", holder: "Nuno Dias")),
            ("SwiftSoup", .mit(year: "2016-2026", holder: "Nabil Chatbi")),
            ("Readability", .apache2(year: "2010", holder: "Arc90 Inc"))
        ], header: "The following software may be included in this product.")
        HelpWindow()
        FeedHealthWindow()
    }
}
