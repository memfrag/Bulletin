//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
@testable import StreamQuery

/// A seeded generator, so a failure is reproducible from its seed rather than
/// being a thing that happened once in CI.
struct SeededGenerator: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}

/// Builds random normalized query trees, for the round-trip property.
enum QueryGenerator {

    /// Values chosen to include the awkward ones: spaces, colons, quotes,
    /// leading minus, and words that are otherwise operators.
    private static let values = [
        "swift", "concurrency", "Ada", "daringfireball", "Dev", "noise",
        "two words", "has:colon", "quote\"inside", "-leading", "OR", "unread",
        "", "Übersicht", "emoji🎉"
    ]

    static func expression(depth: Int, using generator: inout SeededGenerator) -> QueryExpression {

        if depth <= 0 || Bool.random(using: &generator) {
            return .clause(clause(using: &generator)).normalized
        }

        switch Int.random(in: 0..<3, using: &generator) {
        case 0:
            let count = Int.random(in: 2...3, using: &generator)
            return QueryExpression.and(
                (0..<count).map { _ in expression(depth: depth - 1, using: &generator) }
            ).normalized
        case 1:
            let count = Int.random(in: 2...3, using: &generator)
            return QueryExpression.or(
                (0..<count).map { _ in expression(depth: depth - 1, using: &generator) }
            ).normalized
        default:
            return QueryExpression.not(expression(depth: depth - 1, using: &generator)).normalized
        }
    }

    static func clause(using generator: inout SeededGenerator) -> QueryClause {
        switch Int.random(in: 0..<4, using: &generator) {
        case 0:
            return .text(values.randomElement(using: &generator)!)
        case 1:
            return .field(
                QueryField.allCases.randomElement(using: &generator)!,
                values.randomElement(using: &generator)!
            )
        case 2:
            return .flag(QueryFlag.allCases.randomElement(using: &generator)!)
        default:
            let bound = DateBound.allCases.randomElement(using: &generator)!
            if Bool.random(using: &generator) {
                return .date(bound, .daysAgo(Int.random(in: 0...365, using: &generator)))
            }
            return .date(bound, .absolute(DateComponents(
                year: Int.random(in: 1990...2050, using: &generator),
                month: Int.random(in: 1...12, using: &generator),
                day: Int.random(in: 1...28, using: &generator)
            )))
        }
    }
}
