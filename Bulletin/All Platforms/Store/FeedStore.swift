//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import FeedIngest
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bulletin", category: "FeedStore")

/// Everything that writes to the article store.
///
/// The parsing and fetching live in `FeedIngest`, which knows nothing about
/// SwiftData. This is the seam where values become models.
@MainActor
final class FeedStore {

    /// Exposed to the OPML extension in this module rather than to callers.
    internal let modelContext: ModelContext
    private let fetcher: FeedFetcher

    init(modelContext: ModelContext, fetcher: FeedFetcher = FeedFetcher()) {
        self.modelContext = modelContext
        self.fetcher = fetcher
    }

    // MARK: - Subscribing

    /// Subscribes to a feed URL, or returns the existing subscription.
    ///
    /// CloudKit mirroring forbids unique constraints, so "do not subscribe
    /// twice" is enforced here rather than by the schema.
    @discardableResult
    func subscribe(to feedURL: URL, title: String = "", folder: Folder? = nil) throws -> Feed {

        if let existing = try feed(withURL: feedURL) {
            return existing
        }

        let feed = Feed(feedURL: feedURL, title: title)
        feed.folder = folder
        modelContext.insert(feed)
        try modelContext.save()
        return feed
    }

    func feed(withURL feedURL: URL) throws -> Feed? {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.feedURL == feedURL }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Refreshing

    /// Fetches every subscribed feed and ingests what comes back.
    ///
    /// - Parameter force: Ignores backoff windows. This is what a deliberate ⌘R
    ///   on a failing feed should do — the user knows better than the schedule.
    func refreshAll(force: Bool = false) async throws -> RefreshSummary {
        let feeds = try modelContext.fetch(FetchDescriptor<Feed>())
        return try await refresh(feeds, force: force)
    }

    func refresh(_ feeds: [Feed], force: Bool = false) async throws -> RefreshSummary {

        var summary = RefreshSummary()
        let now = Date()

        // Decide what to ask for, and skip anything still backing off.
        var requests: [(url: URL, validators: FeedValidators)] = []
        var feedsByURL: [URL: Feed] = [:]

        for feed in feeds {
            guard let url = feed.feedURL else { continue }

            let state = try fetchState(forFeedID: feed.id)

            if !force, let backoffUntil = state.backoffUntil, backoffUntil > now {
                summary.skippedFeedCount += 1
                continue
            }

            feedsByURL[url] = feed
            requests.append((url, FeedValidators(etag: state.etag, lastModified: state.lastModified)))
        }

        guard !requests.isEmpty else {
            summary.finishedAt = Date()
            return summary
        }

        let outcomes = await fetcher.fetchAll(requests)

        for (url, outcome) in outcomes {
            guard let feed = feedsByURL[url] else { continue }
            let state = try fetchState(forFeedID: feed.id)

            switch outcome {
            case .notModified:
                summary.unchangedFeedCount += 1
                recordSuccess(feed: feed, state: state, validators: nil)

            case .fetched(let parsed, let validators):
                summary.refreshedFeedCount += 1
                summary.newArticleCount += ingest(parsed, into: feed)
                recordSuccess(feed: feed, state: state, validators: validators)

            case .failed(let error, let retryAfter):
                summary.failedFeedCount += 1
                recordFailure(feed: feed, state: state, error: error, retryAfter: retryAfter)
                log.warning("Refresh failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        try modelContext.save()
        summary.finishedAt = Date()
        return summary
    }

    // MARK: - Ingest

    /// Inserts the items that are new, and returns how many there were.
    ///
    /// Identity is `(feed, guid)`. A feed reusing a guid for different content
    /// is a broken feed; treating a repeated guid as the same article is what
    /// stops an edited post from arriving twice.
    private func ingest(_ parsed: ParsedFeed, into feed: Feed) -> Int {

        if feed.title.isEmpty, !parsed.title.isEmpty {
            feed.title = parsed.title
        }
        if feed.homePageURL == nil {
            feed.homePageURL = parsed.homePageURL
        }

        let existingGUIDs = Set((feed.articles ?? []).map(\.guid))
        var inserted = 0

        for item in parsed.items {
            guard !item.guid.isEmpty, !existingGUIDs.contains(item.guid) else { continue }

            let article = Article(guid: item.guid, feed: feed, title: item.title)
            article.author = item.author
            article.url = item.url
            article.canonicalURL = item.url.flatMap(CanonicalURL.canonicalize)
            article.summary = item.contentHTML
            article.publishedAt = item.publishedAt

            let status = ArticleStatus(article: article)
            modelContext.insert(article)
            modelContext.insert(status)
            article.status = status

            inserted += 1
        }

        return inserted
    }

    // MARK: - Fetch bookkeeping

    private func fetchState(forFeedID feedID: UUID) throws -> FeedFetchState {
        let descriptor = FetchDescriptor<FeedFetchState>(
            predicate: #Predicate { $0.feedID == feedID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let state = FeedFetchState(feedID: feedID)
        modelContext.insert(state)
        return state
    }

    private func recordSuccess(feed: Feed, state: FeedFetchState, validators: FeedValidators?) {
        let now = Date()
        // Only overwrite validators on a 200. A 304 does not resend them, and
        // clearing them would make every subsequent refresh unconditional.
        if let validators {
            state.etag = validators.etag
            state.lastModified = validators.lastModified
        }
        state.lastFetchedAt = now
        state.backoffUntil = nil
        state.consecutiveFailureCount = 0

        feed.lastFetchedAt = now
        feed.consecutiveFailureCount = 0
        feed.lastFailureMessage = nil
    }

    private func recordFailure(
        feed: Feed,
        state: FeedFetchState,
        error: FeedFetchError,
        retryAfter: TimeInterval?
    ) {
        state.consecutiveFailureCount += 1
        feed.consecutiveFailureCount = state.consecutiveFailureCount
        feed.lastFailureMessage = error.localizedDescription

        // A permanent failure still backs off rather than retrying forever, but
        // the feed stays subscribed — unsubscribing is the user's call.
        let interval = retryAfter
            ?? FeedFetcher.backoffInterval(afterFailures: state.consecutiveFailureCount)
        state.backoffUntil = Date().addingTimeInterval(interval)
    }
}
