//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Renders a syntax tree back to query text.
///
/// The text form is canonical — it is what a `Stream` stores and what the rule
/// builder displays — so this has to produce something that parses back to the
/// same tree, every time. `RoundTripTests` holds it to that.
public enum QuerySerializer {

    public static func string(from expression: QueryExpression) -> String {
        text(for: expression, parentPrecedence: .top)
    }

    // MARK: - Precedence

    private enum Precedence: Int {
        case top = 0
        case or = 1
        case and = 2
        case not = 3
    }

    private static func text(for expression: QueryExpression, parentPrecedence: Precedence) -> String {

        switch expression {
        case .always:
            return ""

        case .clause(let clause):
            return text(for: clause)

        case .not(let inner):
            // A group under a negation always gets parentheses: `-(a b)` means
            // something quite different from `-a b`.
            let needsParentheses: Bool
            switch inner {
            case .clause: needsParentheses = false
            default: needsParentheses = true
            }
            let innerText = text(for: inner, parentPrecedence: .not)
            return needsParentheses ? "-(\(innerText))" : "-\(innerText)"

        case .and(let children):
            let joined = children
                .map { text(for: $0, parentPrecedence: .and) }
                .joined(separator: " ")
            // AND binds tighter than OR, so an AND inside an OR needs no
            // parentheses, but one inside a NOT does.
            return parentPrecedence.rawValue > Precedence.and.rawValue ? "(\(joined))" : joined

        case .or(let children):
            let joined = children
                .map { text(for: $0, parentPrecedence: .or) }
                .joined(separator: " OR ")
            return parentPrecedence.rawValue > Precedence.or.rawValue ? "(\(joined))" : joined
        }
    }

    // MARK: - Clauses

    static func text(for clause: QueryClause) -> String {
        switch clause {
        case .text(let value):
            return quoteIfNeeded(value)

        case .field(let field, let value):
            return "\(field.rawValue):\(quoteIfNeeded(value))"

        case .flag(let flag):
            return flag.rawValue

        case .date(let bound, let value):
            return "\(bound.rawValue):\(text(for: value))"
        }
    }

    private static func text(for value: DateValue) -> String {
        switch value {
        case .daysAgo(let days):
            return "\(days)d"
        case .absolute(let components):
            let year = components.year ?? 2000
            let month = components.month ?? 1
            let day = components.day ?? 1
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    /// Quotes a value that would otherwise re-lex as something else.
    ///
    /// Whitespace and parentheses would split it; a colon would make it look
    /// like a field; an empty value would vanish entirely; and a bare `OR`
    /// would become an operator.
    private static func quoteIfNeeded(_ value: String) -> String {
        let needsQuoting = value.isEmpty
            || value.contains(where: { $0.isWhitespace })
            || value.contains(":")
            || value.contains("(")
            || value.contains(")")
            || value.contains("\"")
            || value.contains("\\")
            || value.hasPrefix("-")
            || ["or", "and", "not"].contains(value.lowercased())
            || QueryFlag.parse(value) != nil

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
