//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import StreamQuery

@Suite("SQL compilation")
struct SQLCompilerTests {

    private let compiler = QuerySQLCompiler(
        referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
    )

    @Test("Flags compile to column comparisons")
    func compilesFlags() {
        #expect(compiler.compile(QueryParser.parse("unread")).whereClause == "is_read = 0")
        #expect(compiler.compile(QueryParser.parse("starred")).whereClause == "is_starred = 1")
        #expect(compiler.compile(QueryParser.parse("annotated")).whereClause == "has_note = 1")
    }

    @Test("AND and OR nest with explicit parentheses")
    func compilesBooleans() {
        // Relying on SQL's own precedence here would be a bug waiting for the
        // first query that mixes the two.
        let compiled = compiler.compile(QueryParser.parse("unread OR starred"))
        #expect(compiled.whereClause == "(is_read = 0 OR is_starred = 1)")

        let mixed = compiler.compile(QueryParser.parse("(unread OR starred) read"))
        #expect(mixed.whereClause == "((is_read = 0 OR is_starred = 1) AND is_read = 1)")
    }

    @Test("Negation wraps its whole subtree")
    func compilesNegation() {
        let compiled = compiler.compile(QueryParser.parse("-(unread starred)"))
        #expect(compiled.whereClause == "NOT ((is_read = 0 AND is_starred = 1))")
    }

    @Test("Values are bound, never interpolated")
    func bindsValues() {
        // A feed title with an apostrophe would end the statement early, and a
        // query is user input.
        let compiled = compiler.compile(QueryParser.parse("title:\"O'Reilly\""))

        #expect(!compiled.whereClause.contains("O'Reilly"))
        #expect(compiled.bindings == [.text("%O'Reilly%")])
    }

    @Test("LIKE wildcards in a search value are escaped")
    func escapesWildcards() {
        // Without escaping, searching for "100%" matches every article.
        let compiled = compiler.compile(QueryParser.parse("title:100%"))
        #expect(compiled.bindings == [.text("%100\\%%")])
        #expect(compiled.whereClause.contains("ESCAPE"))
    }

    @Test("A folder matches itself and its descendants, but not a similar name")
    func compilesFolderPrefix() {
        let compiled = compiler.compile(QueryParser.parse("folder:Dev"))

        // `/Dev` and `/Dev/Swift` must match; `/MyDev` must not, which is why
        // the leading separator is part of the pattern.
        #expect(compiled.bindings == [.text("/Dev"), .text("/Dev/%")])
    }

    @Test("A tag matches exactly, not as a prefix")
    func compilesTagDelimiters() {
        let compiled = compiler.compile(QueryParser.parse("tag:dev"))
        // Stored delimited, so `dev` cannot match `devops`.
        #expect(compiled.bindings == [.text("%|dev|%")])
    }

    @Test("Relative dates resolve against the reference date")
    func compilesRelativeDates() {
        let compiled = compiler.compile(QueryParser.parse("after:7d"))
        #expect(compiled.whereClause == "sort_date >= ?")

        guard case .double(let seconds)? = compiled.bindings.first else {
            Issue.record("Expected a bound date")
            return
        }
        let expected = Calendar.current.date(
            byAdding: .day, value: -7, to: Date(timeIntervalSince1970: 1_800_000_000)
        )!
        #expect(abs(seconds - expected.timeIntervalSince1970) < 1)
    }

    @Test("Free text goes to the full-text index as a quoted phrase")
    func compilesFullText() {
        // FTS5 has its own query syntax that user input is not written in, so a
        // stray operator must be a search term rather than a syntax error.
        let compiled = compiler.compile(QueryParser.parse("\"swift concurrency\""))
        #expect(compiled.whereClause.contains("articles_fts MATCH ?"))
        #expect(compiled.bindings == [.text("\"swift concurrency\"")])
    }

    @Test("An empty query matches every row")
    func compilesEmptyQuery() {
        let compiled = compiler.compile(.always)
        #expect(compiled.whereClause == "1")
        #expect(compiled.bindings.isEmpty)
    }

    @Test("A realistic query compiles whole")
    func compilesRealisticQuery() {
        let compiled = compiler.compile(
            QueryParser.parse("unread folder:Dev -tag:noise title:swift after:7d")
        )

        #expect(compiled.whereClause.hasPrefix("(is_read = 0 AND"))
        #expect(compiled.whereClause.contains("NOT (tags LIKE ?"))
        #expect(compiled.bindings.count == 5)
    }
}
