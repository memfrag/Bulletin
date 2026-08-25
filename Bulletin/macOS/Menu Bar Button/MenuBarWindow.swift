//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftData

/// The unread count in the menu bar.
struct MenuBarWindow: Scene {

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopup()
                .appEnvironment(.default)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Label

/// The icon, and the count beside it when there is one.
private struct MenuBarLabel: View {

    @Query(filter: #Predicate<Article> { $0.status?.isRead == false })
    private var unread: [Article]

    var body: some View {
        // A zero would be a permanent "0" sitting in the menu bar of an app
        // that has nothing to say.
        if unread.isEmpty {
            Image(systemName: "newspaper")
        } else {
            Label {
                Text(unread.count, format: .number)
            } icon: {
                Image(systemName: "newspaper.fill")
            }
        }
    }
}
