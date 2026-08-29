//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

struct GeneralSettingsTab: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Picker(selection: $settings.colorScheme) {
                Text("System", comment: "Follow the system appearance").tag(AppColorScheme.system)
                Text("Light", comment: "Light appearance").tag(AppColorScheme.light)
                Text("Dark", comment: "Dark appearance").tag(AppColorScheme.dark)
            } label: {
                Text("Appearance:", comment: "Settings label")
            }
            .pickerStyle(.segmented)

            Section {
                Picker(selection: $settings.staleRefreshHours) {
                    Text("Every time", comment: "Refresh-on-activation option").tag(0)
                    Text("After 1 hour", comment: "Refresh-on-activation option").tag(1)
                    Text("After 4 hours", comment: "Refresh-on-activation option").tag(4)
                    Text("After 8 hours", comment: "Refresh-on-activation option").tag(8)
                    Text("After 24 hours", comment: "Refresh-on-activation option").tag(24)
                    Text("Never", comment: "Refresh-on-activation option")
                        .tag(AppSettings.neverRefreshOnActivation)
                } label: {
                    Text("Refresh when returning to Bulletin:", comment: "Settings label")
                }

                Text("Bulletin never polls in the background. Feeds are fetched when you come back to the app after this long, and whenever you ask with \u{2318}R.",
                     comment: "Explanation of the refresh setting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker(selection: $settings.bodyRetentionDays) {
                    Text("7 days", comment: "Retention option").tag(7)
                    Text("30 days", comment: "Retention option").tag(30)
                    Text("90 days", comment: "Retention option").tag(90)
                    Text("Forever", comment: "Retention option").tag(0)
                } label: {
                    Text("Keep article text for:", comment: "Settings label")
                }

                Text("Article titles, dates and links are always kept, so search and streams stay complete. Only the downloaded text is removed, and it is fetched again if you reopen the article.",
                     comment: "Explanation of the retention setting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// Previews use the mock environment, which only exists in DEBUG builds.
#if DEBUG
#Preview {
    GeneralSettingsTab()
        .previewEnvironment()
}
#endif
