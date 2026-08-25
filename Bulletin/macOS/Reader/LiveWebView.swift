//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import WebKit

/// The page as the publisher made it.
///
/// The last resort, for paywalls, interactive pieces, and anything both
/// extractors mangle. Scripting is on because the point is that this is the
/// real page — which is exactly why it is opt-in per feed rather than a default.
struct LiveWebView: NSViewRepresentable {

    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
