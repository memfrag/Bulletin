//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftUI

/// Wraps an article's content in the reader's own document.
///
/// The publisher's markup is kept; the publisher's *styling* is not. Everything
/// visual comes from the stylesheet here, which is what makes every article look
/// like the same app rather than like the site it came from.
enum ReaderDocument {

    struct Style {
        var fontSize: Double
        var lineWidth: Double
        var usesSerif: Bool
        var colorScheme: ColorScheme
    }

    static func html(for article: Article, body: String, notice: String? = nil, style: Style) -> String {

        let byline = [article.author, article.feed?.displayTitle]
            .compactMap { $0 }
            .joined(separator: " · ")

        let date = article.publishedAt.map {
            $0.formatted(date: .long, time: .shortened)
        } ?? ""

        let separator = (byline.isEmpty || date.isEmpty) ? "" : " · "

        let noticeHTML = notice.map {
            "<p class=\"notice\">\(escape($0))</p>"
        } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(stylesheet(style))</style>
        </head>
        <body>
        <article>
          <header>
            <h1>\(escape(article.displayTitle))</h1>
            <p class="byline">\(escape(byline))\(separator)\(escape(date))</p>
          </header>
          \(noticeHTML)
          \(body)
        </article>
        </body>
        </html>
        """
    }

    // MARK: - Style

    private static func stylesheet(_ style: Style) -> String {

        let isDark = style.colorScheme == .dark
        let text = isDark ? "#e8e8ea" : "#1a1a1c"
        let secondary = isDark ? "#9a9aa0" : "#6a6a70"
        let rule = isDark ? "#3a3a3e" : "#dcdce0"
        let codeBackground = isDark ? "#232326" : "#f3f3f5"
        let link = isDark ? "#7fb2ff" : "#0a58ca"
        let noticeBackground = isDark ? "#2c2620" : "#fdf6e8"
        let noticeText = isDark ? "#e0c088" : "#8a6414"

        let bodyFont = style.usesSerif
            ? "\"New York\", ui-serif, Georgia, serif"
            : "-apple-system, \"SF Pro Text\", system-ui, sans-serif"

        let displayFont = style.usesSerif
            ? "\"New York\", ui-serif, Georgia, serif"
            : "-apple-system, \"SF Pro Display\", system-ui, sans-serif"

        return """
        :root { color-scheme: \(isDark ? "dark" : "light"); }

        html { -webkit-text-size-adjust: 100%; }

        body {
          margin: 0;
          background: transparent;
          color: \(text);
          font: \(Int(style.fontSize))px/1.65 \(bodyFont);
          -webkit-font-smoothing: antialiased;
        }

        article {
          max-width: \(Int(style.lineWidth))px;
          margin: 0 auto;
          padding: 40px 32px 96px;
        }

        h1 {
          font: 700 \(Int(style.fontSize * 1.75))px/1.2 \(displayFont);
          letter-spacing: -0.02em;
          margin: 0 0 8px;
        }

        h2, h3, h4 { line-height: 1.25; margin: 1.8em 0 0.5em; font-family: \(displayFont); }
        h2 { font-size: \(Int(style.fontSize * 1.3))px; }
        h3 { font-size: \(Int(style.fontSize * 1.12))px; }

        .byline {
          color: \(secondary);
          font-size: \(Int(style.fontSize * 0.8))px;
          margin: 0 0 28px;
          padding-bottom: 20px;
          border-bottom: 1px solid \(rule);
        }

        /* Says why you are looking at a summary instead of the article. */
        .notice {
          background: \(noticeBackground);
          color: \(noticeText);
          font-size: \(Int(style.fontSize * 0.82))px;
          padding: 10px 14px;
          border-radius: 8px;
          margin: 0 0 24px;
        }

        p { margin: 0 0 1.15em; }

        a { color: \(link); text-decoration-thickness: 1px; text-underline-offset: 2px; }

        /* Images and embeds must never push the text column sideways. */
        img, video, iframe, table { max-width: 100%; height: auto; }

        img { border-radius: 6px; display: block; margin: 1.5em auto; }

        figure { margin: 1.5em 0; }
        figcaption { color: \(secondary); font-size: \(Int(style.fontSize * 0.8))px; text-align: center; }

        blockquote {
          margin: 1.5em 0;
          padding: 0 0 0 1.2em;
          border-left: 3px solid \(rule);
          color: \(secondary);
        }

        pre, code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: \(Int(style.fontSize * 0.85))px;
        }

        code { background: \(codeBackground); padding: 0.15em 0.35em; border-radius: 4px; }

        pre {
          background: \(codeBackground);
          padding: 14px 16px;
          border-radius: 8px;
          overflow-x: auto;
        }

        pre code { background: none; padding: 0; }

        hr { border: none; border-top: 1px solid \(rule); margin: 2em 0; }

        table { border-collapse: collapse; font-size: \(Int(style.fontSize * 0.9))px; }
        th, td { border: 1px solid \(rule); padding: 6px 10px; text-align: left; }
        """
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
