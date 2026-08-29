//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import StreamQuery

/// One condition line in the rule builder.
///
/// The shape of the row follows what was picked: a state flag needs no value, a
/// field needs a text box, and a date needs a number and a unit. Showing an
/// inert text field beside "is unread" would only invite people to type in it.
struct QueryRowEditor: View {

    @Binding var row: QueryBuilderRow

    var onDelete: (() -> Void)?

    /// What kind of condition this row is, which is what the first picker sets.
    private enum Kind: Hashable {
        case flag
        case field(QueryField)
        case date(DateBound)
        case text
    }

    private var kind: Kind {
        switch row.clause {
        case .flag: .flag
        case .field(let field, _): .field(field)
        case .date(let bound, _): .date(bound)
        case .text: .text
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $row.isNegated) {
                Text("Not", comment: "Negates a single condition")
            }
            .toggleStyle(.checkbox)

            Picker(selection: kindBinding) {
                Text("State", comment: "Condition kind: article state").tag(Kind.flag)
                ForEach(QueryField.allCases, id: \.self) { field in
                    Text(title(for: field)).tag(Kind.field(field))
                }
                ForEach(DateBound.allCases, id: \.self) { bound in
                    Text(title(for: bound)).tag(Kind.date(bound))
                }
                Text("Text", comment: "Condition kind: full-text search").tag(Kind.text)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .fixedSize()

            valueEditor

            Spacer(minLength: 0)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.callout)
    }

    // MARK: - Value

    @ViewBuilder
    private var valueEditor: some View {
        switch row.clause {
        case .flag(let flag):
            Picker(selection: flagBinding(flag)) {
                ForEach(QueryFlag.allCases, id: \.self) { option in
                    Text(title(for: option)).tag(option)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .fixedSize()

        case .field(let field, let value):
            TextField(text: fieldValueBinding(field, value), prompt: prompt(for: field)) {
                EmptyView()
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(maxWidth: 220)

        case .date(let bound, let value):
            DateValueEditor(value: dateValueBinding(bound, value))

        case .text(let value):
            TextField(
                text: textBinding(value),
                prompt: Text("words to look for", comment: "Full-text condition placeholder")
            ) {
                EmptyView()
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(maxWidth: 220)
        }
    }

    // MARK: - Bindings

    private var kindBinding: Binding<Kind> {
        Binding(
            get: { kind },
            set: { newKind in
                // Changing the kind keeps whatever value made sense, so picking
                // the wrong field and correcting it does not clear what was typed.
                let carried = currentValueText
                switch newKind {
                case .flag:
                    row.clause = .flag(.unread)
                case .field(let field):
                    row.clause = .field(field, carried)
                case .date(let bound):
                    row.clause = .date(bound, .daysAgo(7))
                case .text:
                    row.clause = .text(carried)
                }
            }
        )
    }

    private var currentValueText: String {
        switch row.clause {
        case .field(_, let value): value
        case .text(let value): value
        case .flag, .date: ""
        }
    }

    private func flagBinding(_ current: QueryFlag) -> Binding<QueryFlag> {
        Binding(get: { current }, set: { row.clause = .flag($0) })
    }

    private func fieldValueBinding(_ field: QueryField, _ value: String) -> Binding<String> {
        Binding(get: { value }, set: { row.clause = .field(field, $0) })
    }

    private func textBinding(_ value: String) -> Binding<String> {
        Binding(get: { value }, set: { row.clause = .text($0) })
    }

    private func dateValueBinding(_ bound: DateBound, _ value: DateValue) -> Binding<DateValue> {
        Binding(get: { value }, set: { row.clause = .date(bound, $0) })
    }

    // MARK: - Titles

    private func title(for field: QueryField) -> String {
        switch field {
        case .title: String(localized: "Title")
        case .author: String(localized: "Author")
        case .feed: String(localized: "Feed")
        case .folder: String(localized: "Folder")
        case .tag: String(localized: "Tag")
        case .url: String(localized: "Link")
        }
    }

    private func title(for bound: DateBound) -> String {
        switch bound {
        case .after: String(localized: "Newer than")
        case .before: String(localized: "Older than")
        }
    }

    private func title(for flag: QueryFlag) -> String {
        switch flag {
        case .unread: String(localized: "is unread")
        case .read: String(localized: "is read")
        case .bookmarked: String(localized: "is bookmarked")
        case .unbookmarked: String(localized: "is not bookmarked")
        case .annotated: String(localized: "has a note")
        }
    }

    private func prompt(for field: QueryField) -> Text {
        switch field {
        case .title: Text(verbatim: "swift")
        case .author: Text(verbatim: "Gruber")
        case .feed: Text(verbatim: "Daring Fireball")
        case .folder: Text(verbatim: "Dev")
        case .tag: Text(verbatim: "ios")
        case .url: Text(verbatim: "example.com")
        }
    }
}

// MARK: - Date Value

/// Either "N days ago" or a calendar date.
private struct DateValueEditor: View {

    @Binding var value: DateValue

    var body: some View {
        HStack(spacing: 6) {
            Picker(selection: modeBinding) {
                Text("days ago", comment: "Relative date mode").tag(true)
                Text("date", comment: "Absolute date mode").tag(false)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .fixedSize()

            switch value {
            case .daysAgo(let days):
                TextField(
                    value: Binding(
                        get: { days },
                        set: { value = .daysAgo(max(0, $0)) }
                    ),
                    format: .number
                ) {
                    EmptyView()
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)

            case .absolute(let components):
                DatePicker(
                    selection: Binding(
                        get: { Calendar.current.date(from: components) ?? Date() },
                        set: { value = .absolute(Calendar.current.dateComponents([.year, .month, .day], from: $0)) }
                    ),
                    displayedComponents: .date
                ) {
                    EmptyView()
                }
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
    }

    private var modeBinding: Binding<Bool> {
        Binding(
            get: {
                if case .daysAgo = value { return true }
                return false
            },
            set: { isRelative in
                // A saved stream saying "the last week" should still mean the
                // last week next month, so relative is the default shape.
                if isRelative {
                    value = .daysAgo(7)
                } else {
                    value = .absolute(Calendar.current.dateComponents([.year, .month, .day], from: Date()))
                }
            }
        )
    }
}
