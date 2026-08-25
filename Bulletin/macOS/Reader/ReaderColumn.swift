//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The trailing column: the article being read.
struct ReaderColumn: View {

    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL

    let articleID: UUID?

    var body: some View {
        if let articleID, let article = library.article(withID: articleID) {
            ArticleReader(article: article)
                .id(articleID)
        } else {
            EmptyPane()
        }
    }
}

// MARK: - Article Reader

private struct ArticleReader: View {

    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL

    let article: Article

    var body: some View {
        @Bindable var library = library

        ArticleContentView(article: article)
            .toolbar {
                ToolbarItemGroup {
                    TextSourceControl(article: article)

                    Button {
                        library.isPresentingTagEditor.toggle()
                    } label: {
                        Label {
                            Text("Tags", comment: "Toolbar action")
                        } icon: {
                            Image(systemName: (article.status?.tags?.isEmpty == false) ? "tag.fill" : "tag")
                        }
                    }
                    .help(Text("Tags", comment: "Toolbar help"))
                    .popover(isPresented: $library.isPresentingTagEditor, arrowEdge: .bottom) {
                        TagEditor(article: article)
                    }

                    Button {
                        library.isPresentingNoteEditor.toggle()
                    } label: {
                        Label {
                            Text("Note", comment: "Toolbar action")
                        } icon: {
                            Image(systemName: article.status?.note != nil ? "note.text" : "square.and.pencil")
                        }
                    }
                    .help(Text("Note", comment: "Toolbar help"))
                    .popover(isPresented: $library.isPresentingNoteEditor, arrowEdge: .bottom) {
                        NoteEditor(article: article)
                    }

                    Button {
                        library.toggleStarred(article)
                    } label: {
                        Label {
                            Text("Star", comment: "Toolbar action")
                        } icon: {
                            Image(systemName: (article.status?.isStarred ?? false) ? "star.fill" : "star")
                        }
                    }
                    .help(Text("Star", comment: "Toolbar help"))

                    Button {
                        library.toggleRead(article)
                    } label: {
                        Label {
                            Text("Toggle Read", comment: "Toolbar action")
                        } icon: {
                            Image(systemName: (article.status?.isRead ?? false) ? "envelope.open" : "envelope")
                        }
                    }
                    .help(Text("Toggle read", comment: "Toolbar help"))

                    if let url = article.url {
                        Button {
                            openURL(url)
                        } label: {
                            Label {
                                Text("Open in Browser", comment: "Toolbar action")
                            } icon: {
                                Image(systemName: "safari")
                            }
                        }
                        .help(Text("Open in browser", comment: "Toolbar help"))
                    }
                }
            }
    }
}
