//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Show settings window by using a SettingsLink SwiftUI view.
struct SettingsWindow: Scene {

    private enum Tabs: Hashable {
        case general
        case reading
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
        }
        .frame(width: 460, height: 380)
    }    
}
