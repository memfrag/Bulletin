//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Something that can find the article on a page.
///
/// Both extractors do their own fetching, because *how* they fetch is the
/// difference between them: one asks for the HTML, the other loads the page in
/// a browser and lets its scripts run.
public protocol ContentExtractor: Sendable {

    func extract(from url: URL) async throws -> ExtractedArticle
}
