//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftUI
import SwiftData
import FeedIngest
import ContentExtraction
import StreamQuery

/// The reading session: what is selected, what the last refresh did, and every
/// action the UI can take on the store.
///
/// Views observe this rather than reaching for a `ModelContext` themselves, so
/// there is one place where reading state is mutated and one place where the
/// dwell timer lives.
@Observable @MainActor
final class Library {

    // MARK: Selection

    var selectedItem: SidebarItem? = .builtInStream(.unread)  {
        didSet {
            guard selectedItem != oldValue else { return }
            selectedArticleID = nil
            // Leaving a stream is what clears it out. Come back to Unread and
            // everything you read is gone, which is the behaviour people expect
            // — it just must not happen mid-scroll.
            retainedArticleIDs = []
            cancelDwell()
            runQuery()
        }
    }

    /// Articles that no longer match the current stream but are still shown.
    ///
    /// An article you are reading must not vanish from the list because you
    /// read it. It stays until you leave the stream.
    private(set) var retainedArticleIDs: [UUID] = []

    var selectedArticleID: UUID? {
        didSet {
            guard selectedArticleID != oldValue else { return }
            scheduleDwellMarkAsRead()
            loadReaderContent()
        }
    }

    // MARK: Presentation
    //
    // Held here rather than in a view because the menu commands drive them, and
    // a command has no view to reach into.

    var isPresentingSubscribeSheet = false

    var isPresentingOPMLImporter = false

    var isPresentingOPMLExporter = false

    var isPresentingStreamEditor = false

    var isPresentingNoteEditor = false

    var isPresentingTagEditor = false

    /// The stream being edited, or `nil` when creating a new one.
    var editingStream: Stream? {
        didSet {
            if editingStream != nil {
                isPresentingStreamEditor = true
            }
        }
    }

    // MARK: Searching

    /// What is in the search field.
    ///
    /// Searching is a live query like any other, so it goes through the same
    /// index and the same grammar as a saved stream — the search field *is* the
    /// query editor, which is what makes "save this as a stream" honest.
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    /// Article ids the index returned, or `nil` when the current view is
    /// answered by SwiftData directly.
    private(set) var matchedArticleIDs: [UUID]?

    /// Canonical URL → the articles sharing it, for collapsing duplicates.
    private(set) var duplicateGroups: [String: [UUID]] = [:]

    // MARK: Reader

    /// What the reader should show for the selected article.
    private(set) var readerContent: ReaderContent = .empty

    /// The article ids currently on screen, in list order.
    ///
    /// Published by the list because it already has them; recomputing the
    /// stream here just to find "the next three" would mean a second fetch on
    /// every selection change.
    var visibleArticleIDs: [UUID] = []

    /// How many articles ahead to extract.
    ///
    /// Enough that arrowing down a stream feels instant, small enough that
    /// skimming past ten articles does not fetch ten pages.
    private let lookaheadCount = 3

    // MARK: Refresh state

    private(set) var isRefreshing = false

    private(set) var lastRefresh: RefreshSummary?

    /// When a refresh was last *started*.
    ///
    /// Recorded at the start rather than the end so that the launch refresh and
    /// an activation arriving at the same moment cannot both decide the feeds
    /// are stale and fetch everything twice.
    private(set) var lastRefreshAttemptAt: Date?

    // MARK: Setup

    private let modelContext: ModelContext
    private let store: FeedStore
    private let textStore: ArticleTextStore
    private let index: SearchIndex?
    private let indexer: ArticleIndexer?

    /// Reports whether iCloud sync is working. Inert while mirroring is off.
    let syncMonitor = SyncMonitor(isEnabled: BulletinModelContainer.isCloudKitMirroringEnabled)

    /// How long an article must stay selected before it counts as read.
    ///
    /// Long enough that arrowing through a list does not burn everything you
    /// pass, short enough that actually reading something always marks it.
    private let dwellDuration: Duration = .seconds(1)

    private var dwellTask: Task<Void, Never>?

    /// How long to wait after the last status change before reindexing.
    ///
    /// Reading down a stream changes status on nearly every keystroke, and each
    /// index update is a transaction with an FTS delete and insert in it.
    /// Batching them turns a burst of keystrokes into one write.
    ///
    /// - Important: This coalesces the **search index only**, never the store.
    ///   SwiftData's fetches do not reflect unsaved changes through the status
    ///   relationship, so deferring `save()` leaves the article list showing
    ///   stale read state — which is precisely what marking-on-read exists to
    ///   avoid. And with automatic mirroring the app does not control when
    ///   CloudKit pushes anyway; Core Data batches its own exports.
    private let indexCoalescingWindow: Duration = .seconds(2)

    private var pendingIndexTask: Task<Void, Never>?

    /// Articles whose index rows are stale.
    private var pendingIndexUpdates: Set<UUID> = []

    convenience init(modelContainer: ModelContainer) {
        self.init(modelContext: modelContainer.mainContext)
    }

    init(
        modelContext: ModelContext,
        fetcher: FeedFetcher = FeedFetcher(),
        indexURL: URL? = SearchIndex.defaultURL
    ) {
        self.modelContext = modelContext
        self.store = FeedStore(modelContext: modelContext, fetcher: fetcher)
        self.textStore = ArticleTextStore(modelContext: modelContext)

        // The index is a cache. If it cannot be opened, every other part of the
        // app still works — searching and saved streams simply return nothing
        // rather than the app refusing to start.
        let index = try? SearchIndex(url: indexURL)
        self.index = index
        self.indexer = index.map { ArticleIndexer(modelContext: modelContext, index: $0) }
    }

    /// Brings the index up to date with the store.
    func prepareIndex() {
        indexer?.rebuildIfNeeded()
    }

    /// Evicts article bodies past the retention window.
    ///
    /// Called at launch rather than on a timer: the store only grows while the
    /// app is running anyway.
    func pruneBodies(retentionDays: Int) {
        textStore.pruneBodies(olderThanDays: retentionDays)
    }

    // MARK: - Refreshing

    func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshAttemptAt = Date()
        defer { isRefreshing = false }

        do {
            lastRefresh = try await store.refreshAll(force: force)
            // New articles have to reach the index before any stream can find
            // them, and the index is the only thing streams are answered from.
            indexer?.rebuildIfNeeded()
            runQuery()
        } catch {
            // A refresh that cannot even read the store is not a per-feed
            // failure, so it is reported as a refresh with nothing in it rather
            // than as feeds having failed.
            lastRefresh = RefreshSummary()
        }
    }

    /// Refreshes if the feeds have gone stale, per the user's setting.
    ///
    /// Called when the app is activated. Coming back to Bulletin after a while
    /// is the one moment an automatic fetch is clearly wanted, and the only one
    /// available without a polling timer.
    func refreshIfStale(olderThan settings: AppSettings) async {
        guard settings.shouldRefresh(lastAttempt: lastRefreshAttemptAt) else { return }
        await refreshAll()
    }

    // MARK: - Subscribing

    /// Finds the feeds a URL offers, without subscribing to any of them.
    func discoverFeeds(at url: URL) async throws -> [DiscoveredFeed] {
        try await FeedDiscovery.discover(at: url)
    }

    @discardableResult
    func subscribe(to url: URL, title: String = "") throws -> Feed {
        try store.subscribe(to: url, title: title)
    }

    func importOPML(at fileURL: URL) throws -> FeedStore.OPMLImportResult {
        try store.importOPML(try Data(contentsOf: fileURL))
    }

    func exportOPML() throws -> String {
        try store.exportOPML()
    }

    /// The feed the user has asked to delete, pending confirmation.
    ///
    /// Deleting a feed takes its articles with it, including bookmarked ones, and
    /// nothing here is recoverable — so it is confirmed rather than undoable.
    var feedPendingDeletion: Feed?

    /// Unsubscribes, and removes everything the feed brought with it.
    ///
    /// SwiftData's cascade reaches the articles and their status. It does not
    /// reach the things keyed by id rather than by relationship: the extracted
    /// bodies in the local store, this machine's fetch bookkeeping, and the
    /// search index — which would otherwise go on returning articles that no
    /// longer exist.
    func unsubscribe(_ feed: Feed) {
        let feedID = feed.id
        let articleIDs = (feed.articles ?? []).map(\.id)

        indexer?.remove(ids: articleIDs)

        for articleID in articleIDs {
            let descriptor = FetchDescriptor<ArticleBody>(
                predicate: #Predicate { $0.articleID == articleID }
            )
            for body in (try? modelContext.fetch(descriptor)) ?? [] {
                modelContext.delete(body)
            }
        }

        let stateDescriptor = FetchDescriptor<FeedFetchState>(
            predicate: #Predicate { $0.feedID == feedID }
        )
        for state in (try? modelContext.fetch(stateDescriptor)) ?? [] {
            modelContext.delete(state)
        }

        // Leaving the selection pointing at a feed that no longer exists shows
        // an empty list with the deleted feed's name still in the title.
        if selectedItem == .feed(feedID) || selectedItem == .folder(feed.folder?.id ?? UUID()) {
            selectedItem = .builtInStream(.unread)
        }
        selectedArticleID = nil

        modelContext.delete(feed)
        save()

        pruneUnusedTags()
        runQuery()
    }

    // MARK: - Reading state

    /// Marks the selected article read after it has been selected long enough.
    ///
    /// Restarted on every selection change, so moving through a list quickly
    /// leaves nothing marked behind you.
    private func scheduleDwellMarkAsRead() {
        cancelDwell()
        guard let articleID = selectedArticleID else { return }

        dwellTask = Task { [weak self, dwellDuration] in
            try? await Task.sleep(for: dwellDuration)
            guard !Task.isCancelled else { return }
            self?.markRead(articleID: articleID)
        }
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
    }

    private func markRead(articleID: UUID) {
        guard let article = article(withID: articleID) else { return }
        setRead(true, on: article)
    }

    func setRead(_ isRead: Bool, on article: Article) {
        let status = status(for: article)
        guard status.isRead != isRead else { return }
        status.isRead = isRead
        status.readAt = isRead ? Date() : nil
        retain(article)
        save()
        scheduleReindex(of: article)
    }

    func toggleRead(_ article: Article) {
        setRead(!(article.status?.isRead ?? false), on: article)
        // An article the user deliberately marked unread must not be marked
        // read again by the dwell timer that is still running for it.
        if article.id == selectedArticleID {
            cancelDwell()
        }
    }

    func toggleBookmarked(_ article: Article) {
        let status = status(for: article)
        status.isBookmarked.toggle()
        status.bookmarkedAt = status.isBookmarked ? Date() : nil
        retain(article)
        save()
        scheduleReindex(of: article)
    }

    func setNote(_ note: String?, on article: Article) {
        let status = status(for: article)
        status.note = (note?.isEmpty ?? true) ? nil : note
        // A note is typed deliberately and is not repeated a second later, so
        // it is written straight away rather than coalesced.
        indexer?.index([article])
        save()
    }

    /// Marks everything in the current selection read.
    func markAllRead(in item: SidebarItem?) {
        let descriptor = ArticleQuery.descriptor(for: item, feedIDs: feedIDs(for: item))
        guard let articles = try? modelContext.fetch(descriptor) else { return }

        var changed: [Article] = []
        for article in articles {
            let status = status(for: article)
            guard !status.isRead else { continue }
            status.isRead = true
            status.readAt = Date()
            changed.append(article)
        }
        indexer?.index(changed)
        // Mark All Read is a deliberate "clear this out", so nothing is
        // retained — the stream empties, which is the point of the command.
        retainedArticleIDs = []
        selectedArticleID = nil
        cancelDwell()
        save()
    }

    // MARK: - Query execution

    private var searchTask: Task<Void, Never>?

    /// Waits for typing to settle before querying.
    ///
    /// Without this every keystroke runs a query and reloads the list, which is
    /// both wasteful and visibly jumpy.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.runQuery()
        }
    }

    /// Works out whether the current view needs the index, and runs it if so.
    func runQuery() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Searching narrows whatever is selected; a saved stream replaces it.
        let queryText: String?
        if !trimmedSearch.isEmpty {
            queryText = [savedStreamQuery, trimmedSearch].compactMap { $0 }.joined(separator: " ")
        } else {
            queryText = savedStreamQuery
        }

        guard let queryText, let indexer else {
            matchedArticleIDs = nil
            duplicateGroups = [:]
            return
        }

        let ids = indexer.ids(matching: queryText)
        matchedArticleIDs = ids
        duplicateGroups = indexer.duplicateGroups(among: ids)
    }

    /// The query text of the selected saved stream, if one is selected.
    private var savedStreamQuery: String? {
        guard case .stream(let id) = selectedItem else { return nil }
        return stream(withID: id)?.queryText
    }

    // MARK: - Saved streams

    func stream(withID id: UUID) -> Stream? {
        try? modelContext.fetch(
            FetchDescriptor<Stream>(predicate: #Predicate { $0.id == id })
        ).first
    }

    @discardableResult
    func saveStream(name: String, queryText: String) -> Stream {
        let stream = Stream(name: name, queryText: queryText)
        stream.sortIndex = (try? modelContext.fetchCount(FetchDescriptor<Stream>())) ?? 0
        modelContext.insert(stream)
        save()
        return stream
    }

    func updateStream(_ stream: Stream, name: String, queryText: String) {
        stream.name = name
        stream.queryText = queryText
        save()
        runQuery()
    }

    func deleteStream(_ stream: Stream) {
        if selectedItem == .stream(stream.id) {
            selectedItem = .builtInStream(.unread)
        }
        modelContext.delete(stream)
        save()
    }

    // MARK: - Text source

    /// The source an article opens with: its own override, or its feed's default.
    func textSource(for article: Article) -> ArticleTextSource {
        article.status?.effectiveTextSource ?? .feed
    }

    /// Moves an article to the next text source, and makes that the feed's default.
    ///
    /// Changing it once fixes the feed rather than the article, which is the
    /// point — a chronically truncated feed should not need fixing every time.
    func cycleTextSource(for article: Article) {
        setTextSource(textSource(for: article).next, for: article, scope: .feed)
    }

    enum TextSourceScope {
        /// Sets the feed's default and clears any per-article override.
        case feed
        /// Sets an override for this article only.
        case article
    }

    func setTextSource(_ source: ArticleTextSource, for article: Article, scope: TextSourceScope) {
        switch scope {
        case .feed:
            article.feed?.textSource = source
            status(for: article).textSourceOverride = nil
        case .article:
            status(for: article).textSourceOverride = source
        }
        save()
        loadReaderContent()
    }

    // MARK: - Reader content

    private var readerLoadTask: Task<Void, Never>?

    /// Fetches whatever the selected article's source needs, then hands it to
    /// the reader.
    private func loadReaderContent() {
        readerLoadTask?.cancel()

        guard let article = selectedArticle else {
            readerContent = .empty
            return
        }

        let source = textSource(for: article)

        switch source {
        case .feed:
            readerContent = .html(article.summary ?? "", source: source)
            prefetchAhead()
            return

        case .liveWebPage:
            if let url = article.url {
                readerContent = .liveWebPage(url)
            } else {
                readerContent = .failed(String(localized: "This article has no address."), source: source)
            }
            prefetchAhead()
            return

        case .nativeExtraction, .readabilityExtraction:
            break
        }

        // A body already extracted shows immediately; only a genuine fetch gets
        // a spinner, so revisiting an article never flashes one.
        if let cached = textStore.cachedBody(articleID: article.id, source: source) {
            readerContent = .html(cached.contentHTML, source: source)
            prefetchAhead()
            return
        }

        readerContent = .loading(source: source)
        let articleID = article.id

        readerLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let html = try await textStore.contentHTML(for: article, source: source)
                guard !Task.isCancelled, selectedArticleID == articleID else { return }
                readerContent = .html(html ?? "", source: source)
            } catch {
                guard !Task.isCancelled, selectedArticleID == articleID else { return }
                // Falling back to the feed's own text beats an error page: a
                // truncated summary is still something to read.
                readerContent = .failedWithFallback(
                    message: error.localizedDescription,
                    fallbackHTML: article.summary ?? "",
                    source: source
                )
            }
            prefetchAhead()
        }
    }

    /// Extracts the next few articles in the current list.
    private func prefetchAhead() {
        guard let selectedArticleID,
              let index = visibleArticleIDs.firstIndex(of: selectedArticleID) else {
            return
        }

        let upcoming = visibleArticleIDs
            .dropFirst(index + 1)
            .prefix(lookaheadCount)
            .compactMap { article(withID: $0) }

        textStore.prefetch(upcoming)
    }

    // MARK: - Lookups

    /// The article currently being read, if any.
    var selectedArticle: Article? {
        selectedArticleID.flatMap(article(withID:))
    }

    func article(withID id: UUID) -> Article? {
        try? modelContext.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        ).first
    }

    func feed(withID id: UUID) -> Feed? {
        try? modelContext.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.id == id })
        ).first
    }

    func folder(withID id: UUID) -> Folder? {
        try? modelContext.fetch(
            FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
        ).first
    }

    /// The feeds a sidebar selection covers, resolving a folder to its whole
    /// subtree.
    func feedIDs(for item: SidebarItem?) -> [UUID] {
        switch item {
        case .feed(let id):
            return [id]

        case .folder(let id):
            guard let folder = try? modelContext.fetch(
                FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })
            ).first else {
                return []
            }
            return folder.feedsIncludingDescendants.map(\.id)

        default:
            return []
        }
    }

    func unreadCounts() -> UnreadCounts {
        (try? UnreadCounts(context: modelContext)) ?? UnreadCounts()
    }

    // MARK: - Private

    // MARK: - Folders

    /// Creates a folder, optionally inside another.
    @discardableResult
    func createFolder(named name: String, parent: Folder? = nil) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(
            name: trimmed.isEmpty ? String(localized: "New Folder") : trimmed,
            parent: parent
        )
        folder.sortIndex = (try? modelContext.fetchCount(FetchDescriptor<Folder>())) ?? 0
        modelContext.insert(folder)
        save()
        return folder
    }

    func renameFolder(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        // The folder's name is a search facet, so every article beneath it has
        // a stale `folder_path` until they are reindexed.
        reindexArticles(under: folder)
        save()
    }

    /// Deletes a folder. Its feeds move up rather than being deleted with it.
    ///
    /// Losing a subscription because a folder was tidied away would be a nasty
    /// surprise; the relationship's nullify rule is what makes this safe.
    func deleteFolder(_ folder: Folder) {
        let orphanedFeeds = folder.feedsIncludingDescendants

        if selectedItem == .folder(folder.id) {
            selectedItem = .builtInStream(.unread)
        }

        for feed in orphanedFeeds {
            feed.folder = nil
        }

        modelContext.delete(folder)
        save()

        indexer?.index(orphanedFeeds.flatMap { $0.articles ?? [] })
        runQuery()
    }

    /// Moves a feed into a folder, or to the top level when `folder` is nil.
    func move(_ feed: Feed, to folder: Folder?) {
        guard feed.folder?.id != folder?.id else { return }
        feed.folder = folder
        // `folder_path` is what `folder:` matches on, so the feed's articles
        // have to be reindexed or the query keeps the old answer.
        indexer?.index(feed.articles ?? [])
        save()
        runQuery()
    }

    /// Moves a folder inside another, or to the top level.
    ///
    /// - Returns: Whether the move was allowed. Dropping a folder into its own
    ///   descendant would detach the whole branch from the tree.
    @discardableResult
    func move(_ folder: Folder, into newParent: Folder?) -> Bool {
        guard folder.id != newParent?.id else { return false }
        guard !isDescendant(newParent, of: folder) else { return false }

        folder.parent = newParent
        reindexArticles(under: folder)
        save()
        runQuery()
        return true
    }

    /// Whether `candidate` sits anywhere beneath `folder`.
    func isDescendant(_ candidate: Folder?, of folder: Folder) -> Bool {
        var node = candidate
        var guardCount = 0
        while let current = node, guardCount < 64 {
            if current.id == folder.id { return true }
            node = current.parent
            guardCount += 1
        }
        return false
    }

    private func reindexArticles(under folder: Folder) {
        let articles = folder.feedsIncludingDescendants.flatMap { $0.articles ?? [] }
        indexer?.index(articles)
    }

    // MARK: - Tags

    /// Every tag in use, alphabetically.
    var allTags: [Tag] {
        let tags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        return tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func tags(on article: Article) -> [Tag] {
        (article.status?.tags ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Applies a tag, creating it if this is the first time it has been used.
    ///
    /// Tag names are matched case-insensitively so that `Swift` and `swift` do
    /// not become two tags that look identical in the sidebar and match
    /// different articles.
    func addTag(named name: String, to article: Article) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let status = status(for: article)
        let existing = allTags.first {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }

        let tag: Tag
        if let existing {
            guard !(status.tags ?? []).contains(where: { $0.id == existing.id }) else { return }
            tag = existing
        } else {
            tag = Tag(name: trimmed)
            modelContext.insert(tag)
        }

        status.tags = (status.tags ?? []) + [tag]
        indexer?.index([article])
        save()
    }

    func removeTag(_ tag: Tag, from article: Article) {
        let status = status(for: article)
        status.tags = (status.tags ?? []).filter { $0.id != tag.id }
        indexer?.index([article])
        save()
    }

    func toggleTag(_ tag: Tag, on article: Article) {
        if tags(on: article).contains(where: { $0.id == tag.id }) {
            removeTag(tag, from: article)
        } else {
            addTag(named: tag.name, to: article)
        }
    }

    /// Removes tags nothing refers to any more.
    ///
    /// A tag list that only ever grows fills up with things removed from the
    /// last article that had them.
    func pruneUnusedTags() {
        let unused = allTags.filter { ($0.statuses ?? []).isEmpty }
        guard !unused.isEmpty else { return }
        for tag in unused {
            modelContext.delete(tag)
        }
        save()
    }

    // MARK: - Coalesced indexing

    /// Notes that an article's index row is stale and schedules the update.
    private func scheduleReindex(of article: Article) {
        pendingIndexUpdates.insert(article.id)

        pendingIndexTask?.cancel()
        pendingIndexTask = Task { [weak self, indexCoalescingWindow] in
            try? await Task.sleep(for: indexCoalescingWindow)
            guard !Task.isCancelled else { return }
            self?.flushPendingWrites()
        }
    }

    /// Writes any batched index updates.
    ///
    /// Called on the coalescing timer and at quit. The store is always already
    /// current — only the index lags, and only for a couple of seconds.
    func flushPendingWrites() {
        pendingIndexTask?.cancel()
        pendingIndexTask = nil

        guard !pendingIndexUpdates.isEmpty else { return }
        let articles = pendingIndexUpdates.compactMap { article(withID: $0) }
        indexer?.index(articles)
        pendingIndexUpdates.removeAll()
    }

    /// Whether any index updates are waiting.
    var hasPendingWrites: Bool {
        !pendingIndexUpdates.isEmpty
    }

    /// Keeps an article on screen even after it stops matching the stream.
    private func retain(_ article: Article) {
        guard !retainedArticleIDs.contains(article.id) else { return }
        retainedArticleIDs.append(article.id)
    }

    /// Every article has a status from ingest, but one can be created here for
    /// anything that predates that guarantee.
    private func status(for article: Article) -> ArticleStatus {
        if let status = article.status {
            return status
        }
        let status = ArticleStatus(article: article)
        modelContext.insert(status)
        article.status = status
        return status
    }

    private func save() {
        try? modelContext.save()
    }
}
