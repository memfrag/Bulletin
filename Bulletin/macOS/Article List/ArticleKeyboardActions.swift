//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Single-key actions on the focused article list.
///
/// Arrow keys and Tab are left to SwiftUI: the list already moves the selection
/// and the split view already moves focus between columns, and re-implementing
/// either would only break the behaviour people already have in their hands.
///
/// Every action here also exists in the Articles menu with a ⌘ equivalent, so
/// nothing is reachable only by knowing it exists.
private struct ArticleKeyboardActions: ViewModifier {

    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL

    let articles: [Article]

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return) {
                guard let url = selectedArticle?.url else { return .ignored }
                openURL(url)
                return .handled
            }
            .onKeyPress(keys: ["s"]) { _ in
                guard let article = selectedArticle else { return .ignored }
                library.toggleStarred(article)
                return .handled
            }
            .onKeyPress(keys: ["u"]) { _ in
                guard let article = selectedArticle else { return .ignored }
                library.toggleRead(article)
                return .handled
            }
            .onKeyPress(keys: ["r"]) { _ in
                Task { await library.refreshAll() }
                return .handled
            }
            .onKeyPress(keys: ["t"]) { _ in
                guard selectedArticle != nil else { return .ignored }
                library.isPresentingTagEditor = true
                return .handled
            }
            .onKeyPress(keys: ["n"]) { _ in
                guard selectedArticle != nil else { return .ignored }
                library.isPresentingNoteEditor = true
                return .handled
            }
    }

    private var selectedArticle: Article? {
        guard let id = library.selectedArticleID else { return nil }
        return articles.first { $0.id == id }
    }
}

extension View {

    /// Adds the single-key article actions to a focused list.
    ///
    /// - Note: `Space` paging the reader still waits on the reader owning its
    ///   own scrolling.
    func articleKeyboardActions(for articles: [Article]) -> some View {
        modifier(ArticleKeyboardActions(articles: articles))
    }
}
