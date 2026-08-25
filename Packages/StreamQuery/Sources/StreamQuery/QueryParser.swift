//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Parses query text into a syntax tree.
///
/// Deliberately forgiving: a half-typed query is the normal state of a search
/// field, and refusing to parse it would mean the results stop updating as the
/// user types. Unknown fields become free text, an unclosed quote runs to the
/// end, and a trailing operator is ignored.
public enum QueryParser {

    /// - Returns: The normalized tree. Empty input is ``QueryExpression/always``.
    public static func parse(_ input: String) -> QueryExpression {
        var tokens = QueryLexer.tokenize(input)[...]
        let expression = parseOr(&tokens)
        return expression.normalized
    }

    // MARK: - Grammar

    private static func parseOr(_ tokens: inout ArraySlice<QueryToken>) -> QueryExpression {
        var branches = [parseAnd(&tokens)]

        while tokens.first == .or {
            tokens = tokens.dropFirst()
            branches.append(parseAnd(&tokens))
        }

        return branches.count == 1 ? branches[0] : .or(branches)
    }

    private static func parseAnd(_ tokens: inout ArraySlice<QueryToken>) -> QueryExpression {
        var terms: [QueryExpression] = []

        while let token = tokens.first, token != .or, token != .closeParen {
            guard let term = parseTerm(&tokens) else { break }
            terms.append(term)
        }

        switch terms.count {
        case 0: return .always
        case 1: return terms[0]
        default: return .and(terms)
        }
    }

    private static func parseTerm(_ tokens: inout ArraySlice<QueryToken>) -> QueryExpression? {
        guard let token = tokens.first else { return nil }

        switch token {
        case .not:
            tokens = tokens.dropFirst()
            // A dangling `-` at the end of a half-typed query is not an error.
            guard let inner = parseTerm(&tokens) else { return nil }
            return .not(inner)

        case .openParen:
            tokens = tokens.dropFirst()
            let inner = parseOr(&tokens)
            if tokens.first == .closeParen {
                tokens = tokens.dropFirst()
            }
            return inner

        case .word(let word):
            tokens = tokens.dropFirst()
            if let flag = QueryFlag(rawValue: word.lowercased()) {
                return .clause(.flag(flag))
            }
            return .clause(.text(word))

        case .quotedWord(let word):
            // Quoted means "search for this", never "interpret this". Without
            // the distinction, a search for the word `unread` would silently
            // become the unread filter.
            tokens = tokens.dropFirst()
            return .clause(.text(word))

        case .pair(let field, let value):
            tokens = tokens.dropFirst()
            return .clause(clause(field: field, value: value))

        case .or, .closeParen:
            return nil
        }
    }

    // MARK: - Clauses

    private static func clause(field: String, value: String) -> QueryClause {

        let name = field.lowercased()

        if let bound = DateBound(rawValue: name), let date = parseDateValue(value) {
            return .date(bound, date)
        }

        if let queryField = QueryField(rawValue: name) {
            return .field(queryField, value)
        }

        // An unrecognised field is treated as text rather than dropped, so a
        // typo degrades to a search instead of silently matching everything.
        return .text("\(field):\(value)")
    }

    /// Parses `7d` or `2026-01-31`.
    static func parseDateValue(_ value: String) -> DateValue? {

        if value.hasSuffix("d"), let days = Int(value.dropLast()), days >= 0 {
            return .daysAgo(days)
        }

        let parts = value.split(separator: "-")
        if parts.count == 3,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
           (1...12).contains(month), (1...31).contains(day) {
            return .absolute(DateComponents(year: year, month: month, day: day))
        }

        return nil
    }
}
