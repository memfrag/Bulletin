//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Applies tags to an article.
///
/// Tags are user-applied and article-level. Nothing here applies one
/// automatically — streams are live queries and never mutate what they match,
/// so a tag means someone decided it.
struct TagEditor: View {

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let article: Article

    @State private var newTagName: String = ""

    private var applied: Set<UUID> {
        Set(library.tags(on: article).map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags", comment: "Tag editor title")
                .font(.headline)

            HStack {
                TextField(
                    text: $newTagName,
                    prompt: Text("New tag", comment: "Tag name placeholder")
                ) {
                    Text("New tag", comment: "Tag name field label")
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(addTag)

                Button(action: addTag) {
                    Image(systemName: "plus")
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            let all = library.allTags
            if all.isEmpty {
                Text("No tags yet.", comment: "Tag editor empty state")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(all) { tag in
                            Toggle(isOn: binding(for: tag)) {
                                Text(tag.name)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func binding(for tag: Tag) -> Binding<Bool> {
        Binding(
            get: { applied.contains(tag.id) },
            set: { _ in library.toggleTag(tag, on: article) }
        )
    }

    private func addTag() {
        library.addTag(named: newTagName, to: article)
        newTagName = ""
    }
}
