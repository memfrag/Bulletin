//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A value to bind into a compiled query.
///
/// Values are never interpolated into the SQL — a feed title containing an
/// apostrophe would break the statement, and a query is user input.
public enum QueryBinding: Equatable, Sendable {
    case text(String)
    case double(Double)
    case integer(Int)
}

/// SQL and its bindings.
public struct CompiledQuery: Equatable, Sendable {

    /// A `WHERE` clause body, without the keyword.
    public let whereClause: String

    public let bindings: [QueryBinding]

    public init(whereClause: String, bindings: [QueryBinding]) {
        self.whereClause = whereClause
        self.bindings = bindings
    }
}

/// Turns a query into SQL against the search index.
///
/// The index's shape is assumed here and defined by the app: a table of
/// articles with the facets as columns, plus an FTS5 table for the text.
public struct QuerySQLCompiler: Sendable {

    /// Now, injectable so that relative dates are testable.
    private let referenceDate: Date

    public init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    public func compile(_ expression: QueryExpression) -> CompiledQuery {
        var bindings: [QueryBinding] = []
        let sql = clause(for: expression.normalized, bindings: &bindings)
        return CompiledQuery(whereClause: sql, bindings: bindings)
    }

    // MARK: - Expressions

    private func clause(for expression: QueryExpression, bindings: inout [QueryBinding]) -> String {

        switch expression {
        case .always:
            return "1"

        case .clause(let queryClause):
            return sql(for: queryClause, bindings: &bindings)

        case .not(let inner):
            return "NOT (\(clause(for: inner, bindings: &bindings)))"

        case .and(let children):
            let parts = children.map { clause(for: $0, bindings: &bindings) }
            return "(" + parts.joined(separator: " AND ") + ")"

        case .or(let children):
            let parts = children.map { clause(for: $0, bindings: &bindings) }
            return "(" + parts.joined(separator: " OR ") + ")"
        }
    }

    // MARK: - Clauses

    private func sql(for clause: QueryClause, bindings: inout [QueryBinding]) -> String {

        switch clause {
        case .text(let value):
            // Free text goes to the full-text index, which is the only part of
            // this that searches article bodies rather than metadata.
            bindings.append(.text(ftsQuery(for: value)))
            return "id IN (SELECT id FROM articles_fts WHERE articles_fts MATCH ?)"

        case .field(let field, let value):
            return sql(for: field, value: value, bindings: &bindings)

        case .flag(let flag):
            switch flag {
            case .unread: return "is_read = 0"
            case .read: return "is_read = 1"
            case .starred: return "is_starred = 1"
            case .unstarred: return "is_starred = 0"
            case .annotated: return "has_note = 1"
            }

        case .date(let bound, let value):
            bindings.append(.double(date(for: value).timeIntervalSince1970))
            // Feeds lie about publication dates often enough that the index
            // stores a resolved sort date, which is what a date bound means.
            return bound == .after ? "sort_date >= ?" : "sort_date <= ?"
        }
    }

    private func sql(for field: QueryField, value: String, bindings: inout [QueryBinding]) -> String {

        switch field {
        case .title:
            bindings.append(.text(like(value)))
            return "title LIKE ? ESCAPE '\\'"

        case .author:
            bindings.append(.text(like(value)))
            return "author LIKE ? ESCAPE '\\'"

        case .feed:
            bindings.append(.text(like(value)))
            return "feed_title LIKE ? ESCAPE '\\'"

        case .folder:
            // Folders match their descendants, so this is a prefix match on the
            // stored path. The leading separator stops `Dev` matching `MyDev`.
            bindings.append(.text("/" + escapeLike(value)))
            bindings.append(.text("/" + escapeLike(value) + "/%"))
            return "(folder_path = ? OR folder_path LIKE ? ESCAPE '\\')"

        case .tag:
            // Tags are stored delimited, so an exact tag match is a substring
            // match on `|tag|` and `dev` does not match `devops`.
            bindings.append(.text("%|" + escapeLike(value.lowercased()) + "|%"))
            return "tags LIKE ? ESCAPE '\\'"

        case .url:
            bindings.append(.text(like(value)))
            return "url LIKE ? ESCAPE '\\'"
        }
    }

    // MARK: - Values

    private func date(for value: DateValue) -> Date {
        switch value {
        case .daysAgo(let days):
            return Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        case .absolute(let components):
            return Calendar.current.date(from: components) ?? referenceDate
        }
    }

    private func like(_ value: String) -> String {
        "%" + escapeLike(value) + "%"
    }

    /// Escapes the wildcards, so searching for `100%` does not match everything.
    private func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Builds an FTS5 MATCH expression for a search term.
    ///
    /// FTS5 has its own query syntax, and a user's search text is not written in
    /// it — a stray `"` or `*` would be a syntax error rather than a search. So
    /// the term is quoted as a literal phrase.
    private func ftsQuery(for value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
