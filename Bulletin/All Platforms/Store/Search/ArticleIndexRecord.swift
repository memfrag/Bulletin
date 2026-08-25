//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// One row of the search index.
///
/// A flat value, deliberately: the index is a derived cache, and building it
/// from SwiftData models here keeps every SQLite call free of model objects.
struct ArticleIndexRecord: Sendable, Equatable {

    var id: UUID
    var feedID: UUID?
    var feedTitle: String
    /// The folder's path, `/Dev/Swift`, so `folder:Dev` is a prefix match.
    var folderPath: String
    var title: String
    var author: String
    var url: String
    var canonicalURL: String
    /// Published date, falling back to ingest time — feeds lie about dates.
    var sortDate: Date
    var isRead: Bool
    var isStarred: Bool
    var hasNote: Bool
    /// Delimited, `|swift|ios|`, so `tag:dev` cannot match `devops`.
    var tags: String
    /// Title plus whatever text is available, for the full-text table.
    var body: String
}

extension ArticleIndexRecord {

    @MainActor
    init(article: Article, body: String = "") {
        let tagNames = (article.status?.tags ?? []).map { $0.name.lowercased() }

        self.init(
            id: article.id,
            feedID: article.feedID,
            feedTitle: article.feed?.displayTitle ?? "",
            folderPath: article.feed?.folder.map { "/" + $0.path.joined(separator: "/") } ?? "",
            title: article.title,
            author: article.author ?? "",
            url: article.url?.absoluteString ?? "",
            canonicalURL: article.canonicalURL?.absoluteString ?? "",
            sortDate: article.sortDate,
            isRead: article.status?.isRead ?? false,
            isStarred: article.status?.isStarred ?? false,
            hasNote: article.status?.note != nil,
            tags: tagNames.isEmpty ? "" : "|" + tagNames.joined(separator: "|") + "|",
            body: body.isEmpty ? (article.summary ?? "") : body
        )
    }
}
