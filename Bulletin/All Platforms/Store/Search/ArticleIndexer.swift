//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import StreamQuery
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bulletin", category: "Indexer")

/// Keeps the search index in step with the store.
///
/// The index is derived, so this is the only thing that writes to it and
/// nothing reads through it for truth. When it and SwiftData disagree,
/// SwiftData wins and the index is rebuilt.
@MainActor
final class ArticleIndexer {

    private let modelContext: ModelContext
    private let index: SearchIndex

    init(modelContext: ModelContext, index: SearchIndex) {
        self.modelContext = modelContext
        self.index = index
    }

    // MARK: - Syncing

    /// Adds or updates rows for specific articles.
    func index(_ articles: [Article]) {
        guard !articles.isEmpty else { return }
        do {
            try index.upsert(articles.map { ArticleIndexRecord(article: $0) })
        } catch {
            log.error("Indexing failed: \(String(describing: error), privacy: .public)")
        }
    }

    func remove(_ articles: [Article]) {
        remove(ids: articles.map(\.id))
    }

    /// Removes rows by id, for articles that have already been deleted.
    func remove(ids: [UUID]) {
        try? index.remove(ids: ids)
    }

    /// Rebuilds the whole index from the store.
    ///
    /// Called when the index is empty or its schema has changed. Cheap enough
    /// to be the answer to any inconsistency, which is why the index is allowed
    /// to be a cache rather than something to migrate.
    func rebuild() {
        do {
            let articles = try modelContext.fetch(FetchDescriptor<Article>())
            try index.removeAll()
            try index.upsert(articles.map { ArticleIndexRecord(article: $0) })
            log.info("Rebuilt the search index with \(articles.count, privacy: .public) articles")
        } catch {
            log.error("Rebuilding the index failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Rebuilds only if the index has fallen behind the store.
    func rebuildIfNeeded() {
        let storeCount = (try? modelContext.fetchCount(FetchDescriptor<Article>())) ?? 0
        guard storeCount != index.count else { return }
        rebuild()
    }

    // MARK: - Querying

    /// Runs query text against the index.
    func ids(matching queryText: String, limit: Int = 1000) -> [UUID] {
        let expression = QueryParser.parse(queryText)
        let compiled = QuerySQLCompiler().compile(expression)
        do {
            return try index.ids(matching: compiled, limit: limit)
        } catch {
            log.error("Query failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Articles that are the same story carried by more than one feed.
    func duplicateGroups(among ids: [UUID]) -> [String: [UUID]] {
        (try? index.duplicateGroups(among: ids)) ?? [:]
    }
}
