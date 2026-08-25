//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// How articles look.
///
/// One reader design rather than a set of themes, with the few controls that
/// genuinely change whether text is comfortable to read: how big it is, how
/// wide the column runs, and whether it is set in a serif.
struct ReadingSettingsTab: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Slider(value: $settings.readerFontSize, in: 13...24, step: 1) {
                    Text("Text size:", comment: "Settings label")
                } minimumValueLabel: {
                    Text(verbatim: "A").font(.caption)
                } maximumValueLabel: {
                    Text(verbatim: "A").font(.title3)
                }

                Slider(value: $settings.readerLineWidth, in: 480...1000, step: 20) {
                    Text("Column width:", comment: "Settings label")
                }

                Text("A narrower column is easier to read; around 70 characters a line is the usual advice.",
                     comment: "Explanation of the column width setting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $settings.readerUsesSerif) {
                    Text("Use a serif typeface", comment: "Settings label")
                }
            }

            Section {
                ReaderSamplePreview()
            } header: {
                Text("Preview", comment: "Settings section header")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

/// Shows the settings applied to real text, because a slider labelled "17" says
/// nothing about whether the result is comfortable.
private struct ReaderSamplePreview: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The Quick Brown Fox", comment: "Sample article title in the reader preview")
                .font(.system(size: settings.readerFontSize * 1.5,
                              weight: .bold,
                              design: settings.readerUsesSerif ? .serif : .default))

            Text("Publishers discovered that a feed carrying the whole article was a feed that never sent anyone to the site, and so a great many of them began sending a paragraph and a link instead.",
                 comment: "Sample article body in the reader preview")
                .font(.system(size: settings.readerFontSize,
                              design: settings.readerUsesSerif ? .serif : .default))
                .lineSpacing(settings.readerFontSize * 0.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// Previews use the mock environment, which only exists in DEBUG builds.
#if DEBUG
#Preview {
    ReadingSettingsTab()
        .previewEnvironment()
}
#endif
