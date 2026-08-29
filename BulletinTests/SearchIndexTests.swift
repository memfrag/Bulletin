//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
import StreamQuery
@testable import Bulletin

/// The whole query path, end to end: text → tree → SQL → real SQLite → ids.
///
/// The parser and the compiler are tested in isolation in the `StreamQuery`
/// package; this is the part that proves the SQL they produce actually runs and
/// selects the right rows.
@MainActor
@Suite("Search index", .serialized)
struct SearchIndexTests {

    private func makeIndex() throws -> SearchIndex {
        try SearchIndex(url: nil)
    }

    private func record(
        _ title: String,
        feedTitle: String = "Example",
        folderPath: String = "",
        author: String = "",
        daysAgo: Int = 0,
        isRead: Bool = false,
        isBookmarked: Bool = false,
        hasNote: Bool = false,
        tags: [String] = [],
        canonicalURL: String = "",
        body: String = ""
    ) -> ArticleIndexRecord {
        ArticleIndexRecord(
            id: UUID(),
            feedID: UUID(),
            feedTitle: feedTitle,
            folderPath: folderPath,
            title: title,
            author: author,
            url: "https://example.com/\(title.hashValue)",
            canonicalURL: canonicalURL,
            sortDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            isRead: isRead,
            isBookmarked: isBookmarked,
            hasNote: hasNote,
            tags: tags.isEmpty ? "" : "|" + tags.joined(separator: "|") + "|",
            body: body
        )
    }

    private func ids(_ index: SearchIndex, _ queryText: String) throws -> [UUID] {
        let compiled = QuerySQLCompiler().compile(QueryParser.parse(queryText))
        return try index.ids(matching: compiled)
    }

    // MARK: - Flags

    @Test("Flags select the right rows")
    func queriesFlags() throws {
        let index = try makeIndex()
        let unread = record("Unread One")
        let read = record("Read One", isRead: true)
        let starred = record("Bookmarked One", isRead: true, isBookmarked: true)
        try index.upsert([unread, read, starred])

        #expect(try ids(index, "unread") == [unread.id])
        #expect(try ids(index, "bookmarked") == [starred.id])
        #expect(try Set(ids(index, "read")) == Set([read.id, starred.id]))
    }

    @Test("Results come back newest first")
    func ordersByDate() throws {
        let index = try makeIndex()
        let old = record("Old", daysAgo: 10)
        let recent = record("Recent", daysAgo: 1)
        let middle = record("Middle", daysAgo: 5)
        try index.upsert([old, recent, middle])

        #expect(try ids(index, "") == [recent.id, middle.id, old.id])
    }

    // MARK: - Fields

    @Test("A folder matches its descendants but not a similarly named folder")
    func queriesFolderDescendants() throws {
        let index = try makeIndex()
        let dev = record("In Dev", folderPath: "/Dev")
        let nested = record("In Dev Swift", folderPath: "/Dev/Swift")
        let lookalike = record("In MyDev", folderPath: "/MyDev")
        try index.upsert([dev, nested, lookalike])

        let matched = try Set(ids(index, "folder:Dev"))
        #expect(matched == Set([dev.id, nested.id]))
        #expect(!matched.contains(lookalike.id))
    }

    @Test("A tag matches exactly, not as a prefix")
    func queriesTagsExactly() throws {
        let index = try makeIndex()
        let swift = record("Swift Post", tags: ["swift"])
        let swiftUI = record("SwiftUI Post", tags: ["swiftui"])
        try index.upsert([swift, swiftUI])

        // Substring matching here would make every `tag:` query quietly wrong.
        #expect(try ids(index, "tag:swift") == [swift.id])
    }

    @Test("Field matches are case-insensitive substrings")
    func queriesFields() throws {
        let index = try makeIndex()
        let target = record("Concurrency in Swift", feedTitle: "Daring Fireball", author: "Ada Lovelace")
        let other = record("Something Else", feedTitle: "Other Feed", author: "Grace Hopper")
        try index.upsert([target, other])

        #expect(try ids(index, "title:swift") == [target.id])
        #expect(try ids(index, "author:lovelace") == [target.id])
        #expect(try ids(index, "feed:fireball") == [target.id])
    }

    // MARK: - Full text

    @Test("Free text searches article bodies, not just titles")
    func queriesFullText() throws {
        let index = try makeIndex()
        let match = record("An Unrelated Headline", body: "The article discusses persistent homology at length.")
        let other = record("Another Headline", body: "This one is about something else entirely.")
        try index.upsert([match, other])

        // Searching only titles would make the archive nearly unsearchable,
        // since a headline rarely contains the words you remember.
        #expect(try ids(index, "homology") == [match.id])
    }

    @Test("Search text with FTS operators in it is treated as a search, not syntax")
    func escapesFullTextSyntax() throws {
        let index = try makeIndex()
        let article = record("Quoted", body: "a phrase with \"quotes\" in it")
        try index.upsert([article])

        // A stray quote must be a search term, not a syntax error.
        #expect(throws: Never.self) {
            _ = try ids(index, "\"quotes\"")
        }
    }

    @Test("Diacritics are folded, so a search finds the accented word")
    func foldsDiacritics() throws {
        let index = try makeIndex()
        let article = record("Cafe", body: "We met at the café on the corner.")
        try index.upsert([article])

        #expect(try ids(index, "cafe") == [article.id])
    }

    // MARK: - Composition

    @Test("A realistic composed query selects exactly the right article")
    func queriesComposed() throws {
        let index = try makeIndex()
        let wanted = record("Swift Concurrency", folderPath: "/Dev", daysAgo: 2, tags: ["ios"])
        let tooOld = record("Swift Concurrency", folderPath: "/Dev", daysAgo: 40, tags: ["ios"])
        let muted = record("Swift Concurrency", folderPath: "/Dev", daysAgo: 2, tags: ["noise"])
        let alreadyRead = record("Swift Concurrency", folderPath: "/Dev", daysAgo: 2, isRead: true)
        let wrongFolder = record("Swift Concurrency", folderPath: "/News", daysAgo: 2)
        try index.upsert([wanted, tooOld, muted, alreadyRead, wrongFolder])

        let matched = try ids(index, "unread folder:Dev -tag:noise title:swift after:7d")
        #expect(matched == [wanted.id])
    }

    @Test("OR widens and negation narrows")
    func queriesBooleans() throws {
        let index = try makeIndex()
        let unread = record("Unread")
        let starred = record("Starred", isRead: true, isBookmarked: true)
        let neither = record("Neither", isRead: true)
        try index.upsert([unread, starred, neither])

        #expect(try Set(ids(index, "unread OR bookmarked")) == Set([unread.id, starred.id]))
        #expect(try ids(index, "read -bookmarked") == [neither.id])
    }

    // MARK: - Maintenance

    @Test("Re-indexing an article replaces its row rather than duplicating it")
    func upsertReplaces() throws {
        let index = try makeIndex()
        var article = record("Before")
        try index.upsert([article])

        article.title = "After"
        article.isRead = true
        try index.upsert([article])

        #expect(index.count == 1)
        #expect(try ids(index, "title:after") == [article.id])
        #expect(try ids(index, "unread").isEmpty)
    }

    @Test("Re-indexing also replaces the full-text row")
    func upsertReplacesFullText() throws {
        let index = try makeIndex()
        var article = record("Post", body: "original wording")
        try index.upsert([article])

        article.body = "replacement wording"
        try index.upsert([article])

        // FTS5 has no upsert, so a stale row here would make an old body
        // findable forever.
        #expect(try ids(index, "original").isEmpty)
        #expect(try ids(index, "replacement") == [article.id])
    }

    @Test("Removing an article removes it from both tables")
    func removesRows() throws {
        let index = try makeIndex()
        let article = record("Doomed", body: "findable text")
        try index.upsert([article])

        try index.remove(ids: [article.id])

        #expect(index.count == 0)
        #expect(try ids(index, "findable").isEmpty)
    }

    // MARK: - Duplicates

    @Test("The same story from several feeds is grouped by canonical URL")
    func findsDuplicateGroups() throws {
        let index = try makeIndex()
        let shared = "https://example.com/the-story"
        let first = record("The Story", feedTitle: "Feed A", canonicalURL: shared)
        let second = record("The Story", feedTitle: "Feed B", canonicalURL: shared)
        let unrelated = record("Something Else", canonicalURL: "https://example.com/other")
        try index.upsert([first, second, unrelated])

        let groups = try index.duplicateGroups(among: [first.id, second.id, unrelated.id])

        #expect(groups.count == 1)
        #expect(Set(groups[shared] ?? []) == Set([first.id, second.id]))
    }

    @Test("Articles with no canonical URL are never grouped")
    func ignoresMissingCanonicalURLs() throws {
        let index = try makeIndex()
        let first = record("One", canonicalURL: "")
        let second = record("Two", canonicalURL: "")
        try index.upsert([first, second])

        // Grouping on an empty string would merge every article that failed
        // canonicalization into one enormous pile.
        #expect(try index.duplicateGroups(among: [first.id, second.id]).isEmpty)
    }
}
