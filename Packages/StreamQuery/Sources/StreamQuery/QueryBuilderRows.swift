//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The rule builder's view of a query.
///
/// A flat list of rows inside nested groups, which is what a Mail-style editor
/// can actually render and edit. This is a *view* onto the syntax tree, not a
/// second source of truth — the text form remains canonical, and this converts
/// in both directions without loss.
public indirect enum QueryBuilderNode: Equatable, Sendable {
    case group(QueryBuilderGroup)
    case row(QueryBuilderRow)
}

/// "Match [all|any] of the following."
public struct QueryBuilderGroup: Equatable, Sendable {

    public enum MatchMode: String, Equatable, Sendable, CaseIterable {
        case all
        case any
    }

    public var mode: MatchMode
    public var isNegated: Bool
    public var children: [QueryBuilderNode]

    public init(mode: MatchMode = .all, isNegated: Bool = false, children: [QueryBuilderNode] = []) {
        self.mode = mode
        self.isNegated = isNegated
        self.children = children
    }
}

/// One condition line.
public struct QueryBuilderRow: Equatable, Sendable {

    public var isNegated: Bool
    public var clause: QueryClause

    public init(isNegated: Bool = false, clause: QueryClause) {
        self.isNegated = isNegated
        self.clause = clause
    }
}

// MARK: - Conversion

extension QueryBuilderGroup {

    /// Builds the editable form of an expression.
    public init(expression: QueryExpression) {
        self = Self.group(from: expression.normalized)
    }

    /// The expression this group describes.
    public var expression: QueryExpression {
        Self.expression(from: .group(self)).normalized
    }

    // MARK: Tree → rows

    private static func group(from expression: QueryExpression) -> QueryBuilderGroup {
        switch expression {
        case .always:
            return QueryBuilderGroup()

        case .clause:
            // A single condition still needs a group to live in, because the
            // editor always shows a match-mode header.
            return QueryBuilderGroup(mode: .all, children: [node(from: expression)])

        case .and(let children):
            return QueryBuilderGroup(mode: .all, children: children.map(node(from:)))

        case .or(let children):
            return QueryBuilderGroup(mode: .any, children: children.map(node(from:)))

        case .not(let inner):
            switch inner {
            case .and(let children):
                return QueryBuilderGroup(mode: .all, isNegated: true, children: children.map(node(from:)))
            case .or(let children):
                return QueryBuilderGroup(mode: .any, isNegated: true, children: children.map(node(from:)))
            default:
                return QueryBuilderGroup(mode: .all, children: [node(from: expression)])
            }
        }
    }

    private static func node(from expression: QueryExpression) -> QueryBuilderNode {
        switch expression {
        case .clause(let clause):
            return .row(QueryBuilderRow(clause: clause))

        case .not(.clause(let clause)):
            return .row(QueryBuilderRow(isNegated: true, clause: clause))

        case .always, .not(.always):
            // Nothing sensible to show as a row, so an empty group stands in.
            // Normalization already removes these; handling them here means a
            // hand-built tree cannot send this into infinite recursion.
            return .group(QueryBuilderGroup())

        case .and, .or, .not:
            return .group(group(from: expression))
        }
    }

    // MARK: Rows → tree

    private static func expression(from node: QueryBuilderNode) -> QueryExpression {
        switch node {
        case .row(let row):
            let clause = QueryExpression.clause(row.clause)
            return row.isNegated ? .not(clause) : clause

        case .group(let group):
            let children = group.children.map(expression(from:))
            let combined: QueryExpression = group.mode == .all ? .and(children) : .or(children)
            return group.isNegated ? .not(combined) : combined
        }
    }
}
