//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The article itself, from whichever of the four sources it is set to use.
struct ArticleContentView: View {

    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let article: Article

    var body: some View {
        switch library.readerContent {

        case .empty:
            EmptyPane()

        case .loading:
            // Only a genuine fetch reaches here — an already-extracted body goes
            // straight to `.html`, so revisiting an article never flashes this.
            VStack(spacing: 10) {
                ProgressView()
                Text("Fetching the full article…", comment: "Reader loading state")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PaneBackground())

        case .html(let html, _):
            document(body: html, notice: nil)

        case .failedWithFallback(let message, let fallbackHTML, _):
            // The feed's own text plus a line saying why. A truncated summary is
            // still something to read; an error page is not.
            document(
                body: fallbackHTML,
                notice: String(localized: "Showing the feed's summary — the full article could not be fetched. \(message)")
            )

        case .failed(let message, _):
            ContentUnavailableView {
                Label("Could Not Load Article", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let url = article.url {
                    Button {
                        openURL(url)
                    } label: {
                        Text("Open in Browser", comment: "Reader failure action")
                    }
                }
            }
            .background(PaneBackground())

        case .liveWebPage(let url):
            // The escape hatch: the real page, scripts and all. Deliberately a
            // separate view from the reader, because nothing here is ours.
            LiveWebView(url: url)
        }
    }

    private func document(body: String, notice: String?) -> some View {
        ArticleWebView(
            html: ReaderDocument.html(
                for: article,
                body: body,
                notice: notice,
                style: ReaderDocument.Style(
                    fontSize: settings.readerFontSize,
                    lineWidth: settings.readerLineWidth,
                    usesSerif: settings.readerUsesSerif,
                    colorScheme: colorScheme
                )
            ),
            baseURL: article.url,
            onNavigate: { url in
                // A link in an article goes to the browser. Following it inside
                // the reader would strand the user in a web view with no way
                // back to what they were reading.
                openURL(url)
            }
        )
        .background(PaneBackground())
    }
}
