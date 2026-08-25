//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import WebKit

/// Renders an HTML document, with scripting disabled.
///
/// Feed content is written by whoever runs the publisher, so it is treated as
/// untrusted: no JavaScript, no navigation away from the loaded document, and
/// every link handed to the browser instead.
struct ArticleWebView: NSViewRepresentable {

    let html: String
    let baseURL: URL?
    let onNavigate: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate

        // Reloading identical HTML would throw away the scroll position on
        // every unrelated state change.
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {

        var onNavigate: (URL) -> Void
        var loadedHTML: String?

        init(onNavigate: @escaping (URL) -> Void) {
            self.onNavigate = onNavigate
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // The initial `loadHTMLString` is the only navigation allowed.
            guard navigationAction.navigationType != .other else {
                decisionHandler(.allow)
                return
            }

            if let url = navigationAction.request.url {
                onNavigate(url)
            }
            decisionHandler(.cancel)
        }
    }
}
