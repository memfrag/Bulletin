//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SQLite3
import StreamQuery
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bulletin", category: "SearchIndex")

/// SQLite's own marker for "copy this string, I will outlive your buffer".
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The index every stream and every search is answered from.
///
/// `#Predicate` is a compile-time macro, so SwiftData cannot evaluate a query a
/// user typed. This can: queries compile to SQL, and the facets live in columns
/// beside an FTS5 table.
///
/// It is a **derived cache**, never a source of truth. Everything in it comes
/// from SwiftData and can be rebuilt from SwiftData, so a corrupt or
/// schema-drifted index is a rebuild rather than data loss.
@MainActor
final class SearchIndex {

    /// Bump when the schema changes. A mismatch rebuilds rather than migrates,
    /// which is the whole advantage of the index being derived.
    private static let schemaVersion = 1

    private var database: OpaquePointer?

    /// Where the index lives: beside the stores, since it is derived from them.
    static var defaultURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("SearchIndex.sqlite")
    }

    // MARK: - Lifecycle

    /// - Parameter url: Where to store the index, or `nil` for an in-memory one.
    init(url: URL?) throws {
        let path = url?.path ?? ":memory:"

        guard sqlite3_open_v2(
            path, &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw SearchIndexError.couldNotOpen(lastErrorMessage)
        }

        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")

        if try storedSchemaVersion() != Self.schemaVersion {
            try dropSchema()
            try createSchema()
            try execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    /// Closes the database.
    ///
    /// Explicit rather than in `deinit`: a nonisolated `deinit` cannot touch
    /// main-actor state, and the index outlives nothing that matters — it is
    /// closed when the window's reading session goes away, or when the process
    /// does, which SQLite handles cleanly either way.
    func close() {
        guard let database else { return }
        sqlite3_close_v2(database)
        self.database = nil
    }

    // MARK: - Schema

    private func createSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS articles (
              id            TEXT PRIMARY KEY,
              feed_id       TEXT,
              feed_title    TEXT NOT NULL DEFAULT '',
              folder_path   TEXT NOT NULL DEFAULT '',
              title         TEXT NOT NULL DEFAULT '',
              author        TEXT NOT NULL DEFAULT '',
              url           TEXT NOT NULL DEFAULT '',
              canonical_url TEXT NOT NULL DEFAULT '',
              sort_date     REAL NOT NULL DEFAULT 0,
              is_read       INTEGER NOT NULL DEFAULT 0,
              is_starred    INTEGER NOT NULL DEFAULT 0,
              has_note      INTEGER NOT NULL DEFAULT 0,
              tags          TEXT NOT NULL DEFAULT ''
            )
            """)

        // Every stream sorts by date, and most filter by feed or read state.
        try execute("CREATE INDEX IF NOT EXISTS articles_sort_date ON articles (sort_date DESC)")
        try execute("CREATE INDEX IF NOT EXISTS articles_feed ON articles (feed_id)")
        try execute("CREATE INDEX IF NOT EXISTS articles_unread ON articles (is_read)")
        try execute("CREATE INDEX IF NOT EXISTS articles_canonical ON articles (canonical_url)")

        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS articles_fts
            USING fts5(id UNINDEXED, title, body, tokenize = 'unicode61 remove_diacritics 2')
            """)
    }

    private func dropSchema() throws {
        try execute("DROP TABLE IF EXISTS articles_fts")
        try execute("DROP TABLE IF EXISTS articles")
    }

    private func storedSchemaVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Writing

    /// Inserts or replaces rows.
    func upsert(_ records: [ArticleIndexRecord]) throws {
        guard !records.isEmpty else { return }

        try execute("BEGIN IMMEDIATE")
        do {
            let article = try prepare("""
                INSERT OR REPLACE INTO articles
                  (id, feed_id, feed_title, folder_path, title, author, url,
                   canonical_url, sort_date, is_read, is_starred, has_note, tags)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """)
            let deleteText = try prepare("DELETE FROM articles_fts WHERE id = ?")
            let insertText = try prepare("INSERT INTO articles_fts (id, title, body) VALUES (?,?,?)")

            defer {
                sqlite3_finalize(article)
                sqlite3_finalize(deleteText)
                sqlite3_finalize(insertText)
            }

            for record in records {
                sqlite3_reset(article)
                bind(article, 1, record.id.uuidString)
                bind(article, 2, record.feedID?.uuidString)
                bind(article, 3, record.feedTitle)
                bind(article, 4, record.folderPath)
                bind(article, 5, record.title)
                bind(article, 6, record.author)
                bind(article, 7, record.url)
                bind(article, 8, record.canonicalURL)
                sqlite3_bind_double(article, 9, record.sortDate.timeIntervalSince1970)
                sqlite3_bind_int(article, 10, record.isRead ? 1 : 0)
                sqlite3_bind_int(article, 11, record.isStarred ? 1 : 0)
                sqlite3_bind_int(article, 12, record.hasNote ? 1 : 0)
                bind(article, 13, record.tags)
                guard sqlite3_step(article) == SQLITE_DONE else {
                    throw SearchIndexError.writeFailed(lastErrorMessage)
                }

                // FTS5 has no upsert, so a replace is a delete then an insert.
                sqlite3_reset(deleteText)
                bind(deleteText, 1, record.id.uuidString)
                _ = sqlite3_step(deleteText)

                sqlite3_reset(insertText)
                bind(insertText, 1, record.id.uuidString)
                bind(insertText, 2, record.title)
                bind(insertText, 3, record.body)
                guard sqlite3_step(insertText) == SQLITE_DONE else {
                    throw SearchIndexError.writeFailed(lastErrorMessage)
                }
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func remove(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let article = try prepare("DELETE FROM articles WHERE id = ?")
        let text = try prepare("DELETE FROM articles_fts WHERE id = ?")
        defer {
            sqlite3_finalize(article)
            sqlite3_finalize(text)
        }

        for id in ids {
            for statement in [article, text] {
                sqlite3_reset(statement)
                bind(statement, 1, id.uuidString)
                _ = sqlite3_step(statement)
            }
        }
    }

    func removeAll() throws {
        try execute("DELETE FROM articles")
        try execute("DELETE FROM articles_fts")
    }

    var count: Int {
        guard let statement = try? prepare("SELECT COUNT(*) FROM articles") else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Reading

    /// Runs a compiled query.
    ///
    /// - Returns: Matching article ids, newest first.
    func ids(matching query: CompiledQuery, limit: Int = 1000) throws -> [UUID] {

        let sql = """
            SELECT id FROM articles
            WHERE \(query.whereClause)
            ORDER BY sort_date DESC
            LIMIT ?
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var index: Int32 = 1
        for binding in query.bindings {
            switch binding {
            case .text(let value): bind(statement, index, value)
            case .double(let value): sqlite3_bind_double(statement, index, value)
            case .integer(let value): sqlite3_bind_int64(statement, index, Int64(value))
            }
            index += 1
        }
        sqlite3_bind_int(statement, index, Int32(limit))

        var ids: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: raw)) else { continue }
            ids.append(id)
        }
        return ids
    }

    /// Groups of articles that are the same story from different feeds.
    ///
    /// - Returns: Canonical URLs with more than one article, mapped to their ids.
    func duplicateGroups(among ids: [UUID]) throws -> [String: [UUID]] {
        guard !ids.isEmpty else { return [:] }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let statement = try prepare("""
            SELECT canonical_url, id FROM articles
            WHERE canonical_url <> '' AND id IN (\(placeholders))
            ORDER BY sort_date DESC
            """)
        defer { sqlite3_finalize(statement) }

        for (offset, id) in ids.enumerated() {
            bind(statement, Int32(offset + 1), id.uuidString)
        }

        var groups: [String: [UUID]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawURL = sqlite3_column_text(statement, 0),
                  let rawID = sqlite3_column_text(statement, 1),
                  let id = UUID(uuidString: String(cString: rawID)) else { continue }
            groups[String(cString: rawURL), default: []].append(id)
        }

        return groups.filter { $0.value.count > 1 }
    }

    // MARK: - SQLite

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.writeFailed(lastErrorMessage)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SearchIndexError.invalidQuery(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        // SQLITE_TRANSIENT: Swift's string buffer does not outlive this call.
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private var lastErrorMessage: String {
        guard let message = sqlite3_errmsg(database) else { return "unknown error" }
        return String(cString: message)
    }
}

// MARK: - Errors

enum SearchIndexError: Error, Equatable {
    case couldNotOpen(String)
    case writeFailed(String)
    case invalidQuery(String)
}
