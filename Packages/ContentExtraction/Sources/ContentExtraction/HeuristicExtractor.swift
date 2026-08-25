//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftSoup

/// Finds the article by scoring the page's elements.
///
/// No WebView and no scripting: the HTML is fetched and parsed, so this is
/// fast, cheap, and leaks nothing beyond the single request. It loses against
/// pages that build their content in JavaScript, which is what the Readability
/// extractor is for.
///
/// The scoring is the same idea Readability uses, reduced to its essentials:
/// prefer elements with a lot of paragraph text and few links. Navigation,
/// related-article rails, and comment threads are all mostly links; article
/// bodies are mostly sentences.
public struct HeuristicExtractor: ContentExtractor {

    private let fetcher: PageFetcher

    public init(fetcher: PageFetcher = PageFetcher()) {
        self.fetcher = fetcher
    }

    public func extract(from url: URL) async throws -> ExtractedArticle {
        let (html, finalURL) = try await fetcher.fetch(url)
        return try Self.extract(html: html, baseURL: finalURL)
    }

    // MARK: - Extraction

    /// Elements that are never article content.
    private static let junkSelectors = [
        "script", "style", "noscript", "template", "svg", "form", "button",
        "nav", "aside", "footer", "header",
        "[role=navigation]", "[role=banner]", "[role=complementary]",
        "[role=search]", "[aria-hidden=true]", "[hidden]"
    ]

    /// Containers that publishers actually use for article bodies, best first.
    ///
    /// Trying these before scoring means the common case is both correct and
    /// nearly free.
    private static let contentSelectors = [
        "article",
        "[role=main] article",
        "main article",
        "[itemprop=articleBody]",
        ".post-content", ".entry-content", ".article-content", ".article-body",
        ".post-body", ".story-body", ".c-entry-content",
        "main",
        "[role=main]"
    ]

    /// Extracts from HTML that has already been fetched.
    ///
    /// Separate from `extract(from:)` so the heuristics can be measured against
    /// a corpus of saved pages instead of against the live web.
    public static func extract(html: String, baseURL: URL?) throws -> ExtractedArticle {

        let document: Document
        do {
            document = try SwiftSoup.parse(html, baseURL?.absoluteString ?? "")
        } catch {
            throw ContentExtractionError.noArticleFound
        }

        let title = (try? document.title())?.trimmed.nilIfEmpty
        let byline = metadata(in: document, names: ["author", "article:author", "twitter:creator"])

        // Strip the chrome before scoring, so a nav bar cannot win on volume.
        for selector in junkSelectors {
            _ = try? document.select(selector).remove()
        }

        guard let candidate = try bestCandidate(in: document) else {
            throw ContentExtractionError.noArticleFound
        }

        try? resolveRelativeURLs(in: candidate, baseURL: baseURL)
        try? removeEmptyElements(in: candidate)

        let contentHTML = (try? candidate.html()) ?? ""
        let plainText = (try? candidate.text()) ?? ""

        guard !plainText.trimmed.isEmpty else {
            throw ContentExtractionError.noArticleFound
        }

        return ExtractedArticle(
            title: title,
            byline: byline,
            contentHTML: contentHTML,
            plainText: plainText
        )
    }

    // MARK: - Candidate selection

    private static func bestCandidate(in document: Document) throws -> Element? {

        // A publisher who marked their article body up properly gets believed.
        for selector in contentSelectors {
            if let element = try? document.select(selector).first(),
               let text = try? element.text(),
               text.count >= ExtractedArticle.minimumUsefulLength {
                return element
            }
        }

        // Otherwise, score every plausible container.
        var best: Element?
        var bestScore = 0.0

        for element in try document.select("div, section, td, main, article") {
            let score = try self.score(element)
            if score > bestScore {
                bestScore = score
                best = element
            }
        }

        return best
    }

    /// How much this element looks like an article body.
    ///
    /// Text length is the base, paragraphs are worth more than loose text, and
    /// link-heavy elements are penalised hard — that single ratio is what
    /// separates an article from a list of other articles.
    private static func score(_ element: Element) throws -> Double {

        let text = try element.text()
        guard text.count >= ExtractedArticle.minimumUsefulLength else { return 0 }

        let linkText = try element.select("a").reduce(0) { total, link in
            total + ((try? link.text().count) ?? 0)
        }
        let linkDensity = Double(linkText) / Double(max(text.count, 1))
        guard linkDensity < 0.5 else { return 0 }

        let paragraphs = try element.select("p").count
        let commas = text.filter { $0 == "," }.count

        var score = Double(text.count)
        score += Double(paragraphs) * 100
        score += Double(commas) * 20
        score *= (1.0 - linkDensity)

        // Elements that merely contain the article should not beat the article.
        // Nesting depth is a rough proxy for "more specific".
        let depth = depthOf(element)
        score *= (1.0 + Double(min(depth, 10)) * 0.02)

        return score
    }

    private static func depthOf(_ element: Element) -> Int {
        var depth = 0
        var node: Element? = element.parent()
        while let current = node, depth < 64 {
            depth += 1
            node = current.parent()
        }
        return depth
    }

    // MARK: - Cleanup

    /// Makes links and images work outside the page they came from.
    ///
    /// The extracted markup is rendered in the reader with a different base, so
    /// a relative `src` would resolve to nothing.
    private static func resolveRelativeURLs(in element: Element, baseURL: URL?) throws {
        guard let baseURL else { return }

        for image in try element.select("img[src]") {
            if let source = try? image.attr("src"),
               let absolute = URL(string: source, relativeTo: baseURL)?.absoluteURL {
                _ = try? image.attr("src", absolute.absoluteString)
            }
        }

        for link in try element.select("a[href]") {
            if let href = try? link.attr("href"),
               let absolute = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                _ = try? link.attr("href", absolute.absoluteString)
            }
        }
    }

    /// Drops elements left holding nothing, which otherwise render as gaps.
    private static func removeEmptyElements(in element: Element) throws {
        for empty in try element.select("p, div, span") {
            let hasText = !((try? empty.text().trimmed) ?? "").isEmpty
            let hasMedia = !((try? empty.select("img, video, iframe, picture, figure").isEmpty()) ?? true)
            if !hasText && !hasMedia {
                try? empty.remove()
            }
        }
    }

    // MARK: - Metadata

    private static func metadata(in document: Document, names: [String]) -> String? {
        for name in names {
            for selector in ["meta[name=\(name)]", "meta[property=\(name)]"] {
                if let content = try? document.select(selector).first()?.attr("content"),
                   let value = content.trimmed.nilIfEmpty {
                    return value
                }
            }
        }
        return nil
    }
}

// MARK: - Helpers

extension String {

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
