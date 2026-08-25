//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import StreamQuery

/// The other half of the round-trip requirement: the rule builder is the
/// primary editor, so a query has to survive being edited as rows and turned
/// back into text.
@Suite("Builder rows")
struct BuilderRowTests {

    @Test("Any generated query survives tree → rows → tree unchanged",
          arguments: [1, 2, 3, 5, 8, 13, 21, 34] as [UInt64])
    func rowsRoundTrip(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)

        for _ in 0..<200 {
            let original = QueryGenerator.expression(depth: 3, using: &generator)
            let rebuilt = QueryBuilderGroup(expression: original).expression

            #expect(rebuilt == original, "seed \(seed): \(original) became \(rebuilt)")
        }
    }

    @Test("The full path holds: rows → text → parse → rows",
          arguments: [7, 11, 42] as [UInt64])
    func fullPathRoundTrips(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)

        for _ in 0..<200 {
            let original = QueryGenerator.expression(depth: 3, using: &generator)
            let rows = QueryBuilderGroup(expression: original)

            // The path a real edit takes: the user changes a row, the text form
            // is regenerated and stored, and the builder is rebuilt from it.
            let text = QuerySerializer.string(from: rows.expression)
            let rebuilt = QueryBuilderGroup(expression: QueryParser.parse(text))

            #expect(rebuilt == rows, "seed \(seed): text was \(text.debugDescription)")
        }
    }

    @Test("An AND becomes match-all and an OR becomes match-any")
    func mapsMatchMode() {
        let all = QueryBuilderGroup(expression: QueryParser.parse("unread starred"))
        #expect(all.mode == .all)
        #expect(all.children.count == 2)

        let any = QueryBuilderGroup(expression: QueryParser.parse("unread OR starred"))
        #expect(any.mode == .any)
    }

    @Test("A negated condition becomes a negated row, not a nested group")
    func mapsNegation() {
        let group = QueryBuilderGroup(expression: QueryParser.parse("unread -tag:noise"))

        guard case .row(let row) = group.children[1] else {
            Issue.record("Expected a row, got \(group.children[1])")
            return
        }
        // Wrapping every `-term` in its own group would give the editor a pile
        // of one-line groups instead of a checkbox.
        #expect(row.isNegated)
        #expect(row.clause == .field(.tag, "noise"))
    }

    @Test("An empty query is an empty match-all group")
    func mapsEmptyQuery() {
        let group = QueryBuilderGroup(expression: .always)
        #expect(group.children.isEmpty)
        #expect(group.mode == .all)
        #expect(group.expression == .always)
    }
}
