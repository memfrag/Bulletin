//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A saved query's syntax tree.
///
/// Kept in a *normal form* so that two queries meaning the same thing are the
/// same value: no single-child `and`/`or`, and no empty groups. Without that,
/// round-tripping through text could not be an identity — `a` and `and([a])`
/// serialize identically but would compare unequal.
public indirect enum QueryExpression: Equatable, Sendable {

    case clause(QueryClause)

    /// Every child must match. Written as juxtaposition: `unread title:swift`.
    case and([QueryExpression])

    /// Any child may match. Written with `OR`.
    case or([QueryExpression])

    case not(QueryExpression)

    /// Matches everything. The empty query.
    case always
}

// MARK: - Normalization

extension QueryExpression {

    /// Collapses the shapes that mean the same thing.
    ///
    /// Applied by the parser and the builder bridge, so every tree in
    /// circulation is already normal and equality means what it looks like.
    public var normalized: QueryExpression {
        switch self {
        case .clause(.text(let value)) where value.isEmpty:
            // An empty search term is not a filter. It also cannot survive a
            // round trip through text, since there would be nothing to read
            // back.
            return .always

        case .clause, .always:
            return self

        case .not(let inner):
            let normalizedInner = inner.normalized

            // A negated empty condition is still no condition. Without this,
            // `.not(.always)` has no text form to serialize and no row to show,
            // and converting it to builder rows recurses forever.
            if normalizedInner == .always {
                return .always
            }

            // Double negation is not preserved: `--a` and `a` are the same
            // query, and keeping the difference would break round-tripping.
            if case .not(let innermost) = normalizedInner {
                return innermost
            }

            return .not(normalizedInner)

        case .and(let children):
            return Self.flatten(children, isConjunction: true)

        case .or(let children):
            return Self.flatten(children, isConjunction: false)
        }
    }

    private static func flatten(_ children: [QueryExpression], isConjunction: Bool) -> QueryExpression {

        var flattened: [QueryExpression] = []

        for child in children.map(\.normalized) {
            switch child {
            case .always where isConjunction:
                // `always AND x` is `x`.
                continue
            case .and(let nested) where isConjunction:
                flattened.append(contentsOf: nested)
            case .or(let nested) where !isConjunction:
                flattened.append(contentsOf: nested)
            default:
                flattened.append(child)
            }
        }

        switch flattened.count {
        case 0: return .always
        case 1: return flattened[0]
        default: return isConjunction ? .and(flattened) : .or(flattened)
        }
    }
}

// MARK: - Clause

/// A single condition.
public enum QueryClause: Equatable, Sendable, Hashable {

    /// Bare words, matched against the article's title and text.
    case text(String)

    /// A field match, such as `title:swift` or `feed:daringfireball`.
    case field(QueryField, String)

    /// A state flag, such as `unread` or `starred`.
    case flag(QueryFlag)

    /// A date bound, such as `after:7d`.
    case date(DateBound, DateValue)
}

/// The fields a query can match on.
public enum QueryField: String, Equatable, Sendable, Hashable, CaseIterable {

    case title
    case author

    /// Matched against a feed's title, so `feed:fireball` works without anyone
    /// having to know a feed's identifier.
    case feed

    /// Matches the folder and everything nested beneath it.
    case folder

    case tag
    case url
}

/// Article state.
public enum QueryFlag: String, Equatable, Sendable, Hashable, CaseIterable {
    case unread
    case read
    case bookmarked
    case unbookmarked
    /// Has a note attached.
    case annotated
}

extension QueryFlag {

    /// Older spellings that still parse.
    ///
    /// Bookmarking used to be called starring. Saved streams written then say
    /// `starred`, and dropping the word would break them silently — the query
    /// would still parse, just as a text search for a word no article contains.
    private static let aliases: [String: QueryFlag] = [
        "starred": .bookmarked,
        "unstarred": .unbookmarked
    ]

    /// Reads a bare keyword, canonical spelling or alias.
    ///
    /// - Important: The serializer decides whether a *search term* needs
    ///   quoting by asking this the same question. Both must agree, or
    ///   searching for the word `starred` would come back as the bookmarked
    ///   filter.
    public static func parse(_ word: String) -> QueryFlag? {
        let lowered = word.lowercased()
        return QueryFlag(rawValue: lowered) ?? aliases[lowered]
    }
}

public enum DateBound: String, Equatable, Sendable, Hashable, CaseIterable {
    case after
    case before
}

/// When.
public enum DateValue: Equatable, Sendable, Hashable {

    /// A number of days back from now, written `7d`.
    ///
    /// Relative rather than absolute on purpose: a saved stream that says
    /// "the last week" should still mean the last week next month.
    case daysAgo(Int)

    /// A calendar date, written `2026-01-31`.
    case absolute(DateComponents)
}
