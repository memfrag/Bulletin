//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import ContentExtraction
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bulletin", category: "ArticleText")

/// Gets the text of an article, from whichever source it is set to use.
///
/// Extraction happens the first time an article is opened, never at refresh:
/// fetching every article at refresh time would turn one ⌘R into hundreds of
/// page loads and would tell every publisher your whole subscription list on a
/// schedule.
@MainActor
final class ArticleTextStore {

    private let modelContext: ModelContext
    private let heuristicExtractor: HeuristicExtractor

    /// Built on first use. It carries a `WKWebView`, so there is no reason to
    /// pay for it in a session where nothing needs escalating.
    private var readabilityExtractor: ReadabilityExtractor?

    /// In-flight extractions, so the lookahead and a user opening the same
    /// article do not fetch the page twice.
    ///
    /// Keyed by article and source, and carrying an `ExtractedArticle` rather
    /// than the model object — SwiftData models are not `Sendable`, so the
    /// value crosses the boundary and the model is created on this side of it.
    private var inFlight: [CacheKey: Task<ExtractedArticle, Error>] = [:]

    private struct CacheKey: Hashable {
        let articleID: UUID
        let source: ArticleTextSource
    }

    init(modelContext: ModelContext, heuristicExtractor: HeuristicExtractor = HeuristicExtractor()) {
        self.modelContext = modelContext
        self.heuristicExtractor = heuristicExtractor
    }

    // MARK: - Reading

    /// The cached body for an article and source, if there is one.
    func cachedBody(articleID: UUID, source: ArticleTextSource) -> ArticleBody? {
        let raw = source.rawValue
        let descriptor = FetchDescriptor<ArticleBody>(
            predicate: #Predicate { $0.articleID == articleID && $0.sourceRawValue == raw }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Extracts an article's text, or returns what was extracted before.
    ///
    /// - Returns: The article markup, or `nil` when the source needs no
    ///   extraction — `.feed` already has its text on the article, and
    ///   `.liveWebPage` has no body because the page *is* the body.
    @discardableResult
    func contentHTML(for article: Article, source: ArticleTextSource) async throws -> String? {

        guard source.requiresPageFetch, source != .liveWebPage else { return nil }
        guard let url = article.url else { throw ContentExtractionError.noArticleFound }

        if let cached = cachedBody(articleID: article.id, source: source) {
            return cached.contentHTML
        }

        let articleID = article.id
        let key = CacheKey(articleID: articleID, source: source)

        let task: Task<ExtractedArticle, Error>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let extractor = { [self] in try await extract(from: url, using: source) }
            task = Task { try await extractor() }
            inFlight[key] = task
        }

        defer { inFlight[key] = nil }

        let extracted = try await task.value

        // Another caller may have stored it while this one was waiting.
        if let cached = cachedBody(articleID: articleID, source: source) {
            return cached.contentHTML
        }

        store(extracted, articleID: articleID, source: source)
        return extracted.contentHTML
    }

    /// Warms the cache for the articles the user is about to arrow onto.
    ///
    /// Bounded and best-effort: failures are ignored, because nothing is
    /// waiting on them and a page that will not load is not news until the user
    /// actually asks for it.
    func prefetch(_ articles: [Article]) {
        for article in articles {
            let source = article.status?.effectiveTextSource ?? article.feed?.textSource ?? .feed
            guard source.requiresPageFetch, source != .liveWebPage else { continue }
            guard cachedBody(articleID: article.id, source: source) == nil else { continue }

            Task { [weak self] in
                _ = try? await self?.contentHTML(for: article, source: source)
            }
        }
    }

    // MARK: - Extraction

    private func extract(from url: URL, using source: ArticleTextSource) async throws -> ExtractedArticle {

        switch source {
        case .nativeExtraction:
            let article = try await heuristicExtractor.extract(from: url)
            // A handful of sentences means the real content was missed. Rather
            // than show a fragment and call it the article, escalate to the
            // extractor that loads the page for real.
            if article.isSubstantial {
                return article
            }
            log.info("Heuristic extraction was thin; escalating to Readability")
            return try await readability().extract(from: url)

        case .readabilityExtraction:
            return try await readability().extract(from: url)

        case .feed, .liveWebPage:
            throw ContentExtractionError.noArticleFound
        }
    }

    private func readability() throws -> ReadabilityExtractor {
        if let readabilityExtractor {
            return readabilityExtractor
        }
        let extractor = try ReadabilityExtractor()
        readabilityExtractor = extractor
        return extractor
    }

    private func store(_ extracted: ExtractedArticle, articleID: UUID, source: ArticleTextSource) {
        let body = ArticleBody(
            articleID: articleID,
            source: source,
            contentHTML: extracted.contentHTML,
            plainText: extracted.plainText
        )
        modelContext.insert(body)
        try? modelContext.save()
    }

    // MARK: - Pruning

    /// Evicts bodies older than the retention window.
    ///
    /// Only bodies — metadata stays forever so that search and streams remain
    /// complete. An evicted body is re-fetched when the article is next opened,
    /// which may 404 by then; the reader offers the live page in that case.
    func pruneBodies(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast

        let descriptor = FetchDescriptor<ArticleBody>(
            predicate: #Predicate { $0.extractedAt < cutoff }
        )
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }

        for body in stale {
            modelContext.delete(body)
        }
        try? modelContext.save()
        log.info("Pruned \(stale.count, privacy: .public) article bodies older than \(days, privacy: .public) days")
    }
}
