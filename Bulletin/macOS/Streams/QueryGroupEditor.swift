//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import StreamQuery

/// One "match all/any of the following" group, and everything inside it.
///
/// Recursive, because the grammar nests. An editor that could only show one
/// level would silently flatten any query that had more, which would break the
/// round-trip the whole design rests on.
struct QueryGroupEditor: View {

    @Binding var group: QueryBuilderGroup

    var isRoot: Bool = false

    /// Removes this group from its parent. `nil` at the root.
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 6) {
                Toggle(isOn: $group.isNegated) {
                    Text("Not", comment: "Negates a whole condition group")
                }
                .toggleStyle(.checkbox)

                Picker(selection: $group.mode) {
                    Text("all", comment: "Match all conditions").tag(QueryBuilderGroup.MatchMode.all)
                    Text("any", comment: "Match any condition").tag(QueryBuilderGroup.MatchMode.any)
                } label: {
                    Text("Match", comment: "Label before the all/any picker")
                }
                .pickerStyle(.menu)
                .fixedSize()

                Text("of the following:", comment: "Trailing half of the match-mode sentence")
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        group.children.append(.row(QueryBuilderRow(clause: .flag(.unread))))
                    } label: {
                        Text("Add Condition", comment: "Adds a row to a condition group")
                    }
                    Button {
                        group.children.append(.group(QueryBuilderGroup()))
                    } label: {
                        Text("Add Group", comment: "Adds a nested condition group")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.callout)

            ForEach(Array(group.children.enumerated()), id: \.offset) { index, child in
                childEditor(at: index, child: child)
                    .padding(.leading, 18)
            }

            if group.children.isEmpty {
                Text("No conditions — this stream matches everything.",
                     comment: "Shown when a condition group is empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(10)
        .background(isRoot ? Color.clear : Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func childEditor(at index: Int, child: QueryBuilderNode) -> some View {
        switch child {
        case .row:
            QueryRowEditor(
                row: Binding(
                    get: {
                        if case .row(let row) = group.children[index] { return row }
                        return QueryBuilderRow(clause: .flag(.unread))
                    },
                    set: { group.children[index] = .row($0) }
                ),
                onDelete: { group.children.remove(at: index) }
            )

        case .group:
            QueryGroupEditor(
                group: Binding(
                    get: {
                        if case .group(let nested) = group.children[index] { return nested }
                        return QueryBuilderGroup()
                    },
                    set: { group.children[index] = .group($0) }
                ),
                onDelete: { group.children.remove(at: index) }
            )
        }
    }
}
