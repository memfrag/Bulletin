//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A note on the whole article.
///
/// Deliberately not anchored to a text range: article bodies are pruned and
/// re-fetched, so any offset-based anchor would rot. A note attached to the
/// article survives its text being thrown away and fetched again.
struct NoteEditor: View {

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let article: Article

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note", comment: "Note editor title")
                .font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 320, height: 140)

            HStack {
                if article.status?.note != nil {
                    Button(role: .destructive) {
                        library.setNote(nil, on: article)
                        dismiss()
                    } label: {
                        Text("Delete", comment: "Delete the note")
                    }
                }

                Spacer()

                Button {
                    library.setNote(text, on: article)
                    dismiss()
                } label: {
                    Text("Save", comment: "Save the note")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .onAppear {
            text = article.status?.note ?? ""
        }
    }
}
