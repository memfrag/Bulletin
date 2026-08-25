//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import StreamQuery

/// The specification of the grammar.
///
/// The rule builder is the primary editor and the text form is what it shows,
/// so a query has to survive conversion in both directions unchanged. Anything
/// that cannot is not in the language — this test is what enforces that, and it
/// is the reason the grammar is as small as it is.
@Suite("Round trip")
struct RoundTripTests {

    @Test("Any generated query survives serialize → parse unchanged",
          arguments: [1, 2, 3, 5, 8, 13, 21, 34, 55, 89] as [UInt64])
    func randomQueriesRoundTrip(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)

        for _ in 0..<200 {
            let original = QueryGenerator.expression(depth: 3, using: &generator)
            let text = QuerySerializer.string(from: original)
            let reparsed = QueryParser.parse(text)

            #expect(
                reparsed == original,
                "seed \(seed): \(original) serialized to \(text.debugDescription) and parsed back as \(reparsed)"
            )
        }
    }

    @Test("Text also survives parse → serialize → parse",
          arguments: [
            "unread",
            "unread folder:Dev",
            "unread folder:Dev -tag:noise title:swift after:7d",
            "starred OR annotated",
            "(unread OR starred) title:swift",
            "-(unread starred)",
            "title:\"swift concurrency\"",
            "before:2026-01-31 after:2025-12-01",
            "feed:daringfireball -read",
            "\"a phrase\" OR \"another phrase\""
          ])
    func writtenQueriesAreStable(text: String) {
        let first = QueryParser.parse(text)
        let second = QueryParser.parse(QuerySerializer.string(from: first))

        // Text a person typed may be spelled differently from the canonical
        // form, but parsing it twice must converge.
        #expect(first == second)
    }

    @Test("An empty query matches everything")
    func emptyQuery() {
        #expect(QueryParser.parse("") == .always)
        #expect(QueryParser.parse("   ") == .always)
        #expect(QuerySerializer.string(from: .always) == "")
    }
}
