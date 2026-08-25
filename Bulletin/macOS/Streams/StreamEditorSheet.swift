//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import StreamQuery

/// Creates and edits a saved stream.
///
/// The rule builder is the primary editor and the query text is shown beneath
/// it, live. Either can be edited: typing in the text field re-parses into
/// rows, and changing a row rewrites the text. They are two views of one thing,
/// which is only possible because the grammar round-trips.
struct StreamEditorSheet: View {

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let stream: Stream?

    @State private var name: String = ""
    @State private var group = QueryBuilderGroup()
    @State private var queryText: String = ""

    /// Set while a change is propagating, so the two editors do not fight.
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text(stream == nil ? "New Stream" : "Edit Stream", comment: "Stream editor title")
                .font(.headline)

            TextField(text: $name, prompt: Text("Unread from Dev", comment: "Stream name placeholder")) {
                Text("Name", comment: "Stream name field label")
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()

            Divider()

            ScrollView {
                QueryGroupEditor(group: $group, isRoot: true)
                    .padding(.trailing, 4)
            }
            .frame(minHeight: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text("Query", comment: "Label above the text form of the query")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(text: $queryText, prompt: Text(verbatim: "unread folder:Dev -tag:noise")) {
                    Text("Query", comment: "Query text field label")
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(.system(.body, design: .monospaced))
            }

            HStack {
                Button(role: .cancel) {
                    close()
                } label: {
                    Text("Cancel", comment: "Dismiss the sheet")
                }

                Spacer()

                Button {
                    save()
                } label: {
                    Text("Save", comment: "Save the stream")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        // A sheet is clipped to its window, so this has to fit inside the
        // smallest window the app allows. At 520 the Save button fell off the
        // bottom edge and the sheet could not be dismissed except by Escape.
        .frame(width: 540, height: 400)
        .onAppear(perform: load)
        .onChange(of: group) { _, newGroup in
            guard !isSyncing else { return }
            isSyncing = true
            queryText = QuerySerializer.string(from: newGroup.expression)
            isSyncing = false
        }
        .onChange(of: queryText) { _, newText in
            guard !isSyncing else { return }
            isSyncing = true
            group = QueryBuilderGroup(expression: QueryParser.parse(newText))
            isSyncing = false
        }
    }

    // MARK: - Actions

    private func load() {
        if let stream {
            name = stream.name
            queryText = stream.queryText
            group = QueryBuilderGroup(expression: QueryParser.parse(stream.queryText))
        } else {
            // A new stream starts from whatever the user was already looking at,
            // because "save this search" is how most of them will begin.
            queryText = library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            group = QueryBuilderGroup(expression: QueryParser.parse(queryText))
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let stream {
            library.updateStream(stream, name: trimmedName, queryText: queryText)
        } else {
            library.saveStream(name: trimmedName, queryText: queryText)
        }
        close()
    }

    private func close() {
        library.editingStream = nil
        library.isPresentingStreamEditor = false
        dismiss()
    }
}
