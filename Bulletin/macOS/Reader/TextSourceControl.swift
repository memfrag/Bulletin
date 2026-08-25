//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Chooses where the article's text comes from.
///
/// Picking a source sets the **feed's** default, not just this article's — a
/// chronically truncated feed should need fixing once, not every time. The
/// per-article override lives in the submenu for the cases where one post on an
/// otherwise fine feed needs different treatment.
struct TextSourceControl: View {

    @Environment(Library.self) private var library

    let article: Article

    private var current: ArticleTextSource {
        library.textSource(for: article)
    }

    var body: some View {
        Menu {
            Picker(selection: sourceBinding) {
                ForEach(ArticleTextSource.allCases) { source in
                    Label(source.title, systemImage: source.systemImage)
                        .tag(source)
                }
            } label: {
                Text("Text Source", comment: "Picker label")
            }
            .pickerStyle(.inline)

            Divider()

            Menu {
                ForEach(ArticleTextSource.allCases) { source in
                    Button {
                        library.setTextSource(source, for: article, scope: .article)
                    } label: {
                        Label(source.title, systemImage: source.systemImage)
                    }
                }
            } label: {
                Text("Only This Article", comment: "Submenu setting a per-article text source")
            }
        } label: {
            Label {
                Text("Text Source", comment: "Toolbar action")
            } icon: {
                Image(systemName: current.systemImage)
            }
        }
        .help(Text("Text source: \(current.title)", comment: "Toolbar help"))
    }

    private var sourceBinding: Binding<ArticleTextSource> {
        Binding(
            get: { current },
            set: { library.setTextSource($0, for: article, scope: .feed) }
        )
    }
}
