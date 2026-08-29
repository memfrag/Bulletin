//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Show settings window by using a SettingsLink SwiftUI view.
struct SettingsWindow: Scene {

    private enum Tabs: Hashable {
        case general
        case reading
        case feeds
    }

    var body: some Scene {
        Settings {
            tabs
                .appEnvironment(.default)
        }
    }
    
    @ViewBuilder var tabs: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)

            ReadingSettingsTab()
                .tabItem {
                    Label("Reading", systemImage: "text.alignleft")
                }
                .tag(Tabs.reading)

            FeedHealthSettingsTab()
                .tabItem {
                    Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(Tabs.feeds)
        }
        // Wide enough for the health table's three columns; the other tabs are
        // comfortable at this size too.
        .frame(width: 620, height: 440)
    }    
}
