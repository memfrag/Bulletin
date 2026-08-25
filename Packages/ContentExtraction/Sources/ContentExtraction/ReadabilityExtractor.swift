//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import WebKit

/// Finds the article using Mozilla's Readability, in a real browser.
///
/// The page is loaded for real — its scripts run — which is the entire reason
/// this exists: a page that assembles its content in JavaScript is invisible to
/// anything that only reads the HTML it was served.
///
/// That is also why it is the escalation rather than the default. Loading a page
/// properly means running whatever the publisher put on it.
///
/// - Note: `@MainActor` because `WKWebView` is.
@MainActor
public final class ReadabilityExtractor: ContentExtractor {

    /// How long to wait for a page before giving up. Some pages never finish.
    private let timeout: Duration

    private let readabilityScript: String

    public init(timeout: Duration = .seconds(20)) throws {
        self.timeout = timeout

        guard let url = Bundle.module.url(forResource: "Readability", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            throw ContentExtractionError.javaScriptFailed("Readability.js is missing from the bundle")
        }
        self.readabilityScript = script
    }

    public nonisolated func extract(from url: URL) async throws -> ExtractedArticle {
        try await MainActor.run { self }.extractOnMainActor(from: url)
    }

    private func extractOnMainActor(from url: URL) async throws -> ExtractedArticle {

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        let loader = PageLoader()
        webView.navigationDelegate = loader

        webView.load(URLRequest(url: url))

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await loader.waitForLoad() }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw ContentExtractionError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }

        return try await run(on: webView)
    }

    // MARK: - Running Readability

    private func run(on webView: WKWebView) async throws -> ExtractedArticle {

        // Readability mutates the document it is given, so it gets a clone.
        // Running it on the live document would leave the page half-dismantled
        // and make a second attempt return nonsense.
        let script = """
        (function() {
          \(readabilityScript)
          try {
            var documentClone = document.cloneNode(true);
            var article = new Readability(documentClone).parse();
            if (!article) { return null; }
            return {
              title: article.title || null,
              byline: article.byline || null,
              content: article.content || "",
              textContent: article.textContent || ""
            };
          } catch (error) {
            return { error: String(error) };
          }
        })();
        """

        let result: Any?
        do {
            result = try await webView.evaluateJavaScript(script)
        } catch {
            throw ContentExtractionError.javaScriptFailed(error.localizedDescription)
        }

        guard let dictionary = result as? [String: Any] else {
            throw ContentExtractionError.noArticleFound
        }

        if let message = dictionary["error"] as? String {
            throw ContentExtractionError.javaScriptFailed(message)
        }

        let contentHTML = dictionary["content"] as? String ?? ""
        let plainText = dictionary["textContent"] as? String ?? ""

        guard !plainText.trimmed.isEmpty else {
            throw ContentExtractionError.noArticleFound
        }

        return ExtractedArticle(
            title: (dictionary["title"] as? String)?.trimmed.nilIfEmpty,
            byline: (dictionary["byline"] as? String)?.trimmed.nilIfEmpty,
            contentHTML: contentHTML,
            plainText: plainText
        )
    }
}

// MARK: - Page Loader

/// Bridges `WKNavigationDelegate` to `async`.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {

    private var continuation: CheckedContinuation<Void, Error>?
    private var outcome: Result<Void, Error>?

    func waitForLoad() async throws {
        if let outcome {
            return try outcome.get()
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        outcome = result
        continuation?.resume(with: result)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(ContentExtractionError.fetchFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(ContentExtractionError.fetchFailed(error.localizedDescription)))
    }
}
