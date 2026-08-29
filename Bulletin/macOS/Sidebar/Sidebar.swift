//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftData
import SwiftUIToolbox

/// The three-column shell: streams, articles, reader.
///
/// The article list stays visible while reading so that moving down a stream
/// with the keyboard never loses your place.
struct Sidebar: View {

    @Environment(Library.self) private var library

    /// Unread articles, fetched once and counted per feed for the badges.
    /// Fetching them as a query means the badges update themselves.
    @Query(filter: #Predicate<Article> { $0.status?.isRead == false })
    private var unreadArticles: [Article]

    @Query(sort: \Stream.sortIndex)
    private var savedStreams: [Stream]

    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortIndex)
    private var rootFolders: [Folder]

    /// Sorted in the view rather than in the query: the store can only order by
    /// the stored `title`, but what the sidebar shows is `displayTitle`, which
    /// prefers a name the user has given the feed.
    @Query(filter: #Predicate<Feed> { $0.folder == nil })
    private var rootFeeds: [Feed]

    private var deletionTitle: String {
        guard let feed = library.feedPendingDeletion else { return "" }
        return String(localized: "Delete \(feed.displayTitle)?")
    }

    var body: some View {
        @Bindable var library = library
        let counts = UnreadCounts(unreadArticles: unreadArticles)

        NavigationSplitView {
            List(selection: $library.selectedItem) {

                Section(header: Text("Streams", comment: "Sidebar section of saved queries")) {
                    ForEach(BuiltInStream.allCases) { stream in
                        NavigationLink(value: SidebarItem.builtInStream(stream)) {
                            Label(stream.title, systemImage: stream.systemImage)
                                .badge(stream == .unread ? counts.total : 0)
                        }
                    }

                    ForEach(savedStreams) { stream in
                        NavigationLink(value: SidebarItem.stream(stream.id)) {
                            Label(stream.name, systemImage: stream.systemImage)
                        }
                        .help(stream.queryText)
                        .contextMenu {
                            Button {
                                library.editingStream = stream
                            } label: {
                                Text("Edit Stream…", comment: "Stream action")
                            }
                            Button(role: .destructive) {
                                library.deleteStream(stream)
                            } label: {
                                Text("Delete Stream", comment: "Stream action")
                            }
                        }
                    }
                }

                Section(header: SubscriptionsHeader()) {
                    if rootFolders.isEmpty && rootFeeds.isEmpty {
                        NoSubscriptionsRow(
                            isPresentingSubscribeSheet: $library.isPresentingSubscribeSheet
                        )
                    } else {
                        ForEach(rootFolders) { folder in
                            FolderRow(folder: folder, counts: counts)
                        }
                        ForEach(rootFeeds.sortedByTitle) { feed in
                            FeedRow(feed: feed, unreadCount: counts[feed.id])
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 240, maxWidth: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarFooter()
            }
            .searchable(
                text: $library.searchText,
                placement: .sidebar,
                prompt: Text("Search articles", comment: "Search field prompt")
            )
        } content: {
            ArticleListColumn(item: library.selectedItem)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 540)
        } detail: {
            ReaderColumn(articleID: library.selectedArticleID)
        }
        .sheet(isPresented: $library.isPresentingSubscribeSheet) {
            SubscribeSheet()
        }
        .sheet(isPresented: $library.isPresentingStreamEditor) {
            StreamEditorSheet(stream: library.editingStream)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { library.feedPendingDeletion != nil },
                set: { if !$0 { library.feedPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: library.feedPendingDeletion
        ) { feed in
            Button(role: .destructive) {
                library.unsubscribe(feed)
                library.feedPendingDeletion = nil
            } label: {
                Text("Delete", comment: "Confirm unsubscribing")
            }
            Button(role: .cancel) {
                library.feedPendingDeletion = nil
            } label: {
                Text("Cancel", comment: "Dismiss the confirmation")
            }
        } message: { feed in
            // Say what is actually lost. "Are you sure?" tells nobody anything,
            // and bookmarked articles going with the feed is the part that stings.
            Text(
                "Its \(feed.articles?.count ?? 0) articles will be deleted too, including any you have bookmarked. This cannot be undone.",
                comment: "Feed deletion confirmation detail"
            )
        }
        .opmlFileImporter(isPresented: $library.isPresentingOPMLImporter)
        .opmlFileExporter(isPresented: $library.isPresentingOPMLExporter)
    }
}

// MARK: - Subscriptions Header

/// The section header, which doubles as the drop target for "out of any folder".
///
/// Dragging to the top level needs somewhere to aim at, and the header is the
/// only fixed piece of the section — the rows beneath it move around.
private struct SubscriptionsHeader: View {

    @Environment(Library.self) private var library

    @State private var isTargeted = false

    var body: some View {
        Text("Subscriptions", comment: "Sidebar section of feeds and folders")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : .clear)
            )
            .dropDestination(for: FeedReference.self) { references, _ in
                let feeds = references.compactMap { library.feed(withID: $0.feedID) }
                guard !feeds.isEmpty else { return false }
                for feed in feeds {
                    library.move(feed, to: nil)
                }
                return true
            } isTargeted: { isTargeted = $0 }
            .dropDestination(for: FolderReference.self) { references, _ in
                let folders = references.compactMap { library.folder(withID: $0.folderID) }
                guard !folders.isEmpty else { return false }
                return folders.reduce(false) { moved, folder in
                    library.move(folder, into: nil) || moved
                }
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Folder Row

/// A folder and everything under it.
///
/// Recursive, because the folder tree is: OPML nests arbitrarily and flattening
/// it on import would quietly rearrange everyone's subscription list.
private struct FolderRow: View {

    @Environment(Library.self) private var library

    let folder: Folder
    let counts: UnreadCounts

    @State private var isTargeted = false
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        DisclosureGroup {
            ForEach((folder.children ?? []).sorted { $0.sortIndex < $1.sortIndex }) { child in
                FolderRow(folder: child, counts: counts)
            }
            ForEach((folder.feeds ?? []).sortedByTitle) { feed in
                FeedRow(feed: feed, unreadCount: counts[feed.id])
            }
        } label: {
            NavigationLink(value: SidebarItem.folder(folder.id)) {
                Label(folder.name, systemImage: isTargeted ? "folder.fill" : "folder")
                    .badge(counts.count(for: folder))
            }
            .draggable(FolderReference(folderID: folder.id))
            .dropDestination(for: FeedReference.self) { references, _ in
                move(references)
            } isTargeted: { isTargeted = $0 }
            .dropDestination(for: FolderReference.self) { references, _ in
                moveFolders(references)
            } isTargeted: { isTargeted = $0 }
            .contextMenu {
                Button {
                    draftName = folder.name
                    isRenaming = true
                } label: {
                    Text("Rename…", comment: "Folder action")
                }

                Button {
                    library.createFolder(named: "", parent: folder)
                } label: {
                    Text("New Folder Inside", comment: "Folder action")
                }

                Divider()

                Button(role: .destructive) {
                    library.deleteFolder(folder)
                } label: {
                    Text("Delete", comment: "Folder action")
                }
            }
            .alert(
                Text("Rename Folder", comment: "Rename folder dialog title"),
                isPresented: $isRenaming
            ) {
                TextField(text: $draftName) {
                    Text("Name", comment: "Folder name field")
                }
                Button {
                    library.renameFolder(folder, to: draftName)
                } label: {
                    Text("Rename", comment: "Confirm renaming a folder")
                }
                Button(role: .cancel) {} label: {
                    Text("Cancel", comment: "Dismiss the dialog")
                }
            }
        }
    }

    /// Nests dropped folders inside this one.
    ///
    /// Refuses a drop into the folder's own descendant, which would detach the
    /// whole branch from the tree.
    private func moveFolders(_ references: [FolderReference]) -> Bool {
        let folders = references.compactMap { library.folder(withID: $0.folderID) }
        guard !folders.isEmpty else { return false }
        return folders.reduce(false) { moved, dragged in
            library.move(dragged, into: folder) || moved
        }
    }

    /// Moves dropped feeds into this folder.
    private func move(_ references: [FeedReference]) -> Bool {
        let feeds = references.compactMap { library.feed(withID: $0.feedID) }
        guard !feeds.isEmpty else { return false }
        for feed in feeds {
            library.move(feed, to: folder)
        }
        return true
    }
}

// MARK: - Feed Row

private struct FeedRow: View {

    @Environment(Library.self) private var library

    let feed: Feed
    let unreadCount: Int

    var body: some View {
        NavigationLink(value: SidebarItem.feed(feed.id)) {
            Label {
                Text(feed.displayTitle)
            } icon: {
                // A feed that has been failing repeatedly says so here rather
                // than in an alert, because one publisher's bad day is not
                // something the reader should stop for.
                if feed.consecutiveFailureCount >= Feed.staleFailureThreshold {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "dot.radiowaves.up.forward")
                }
            }
            .badge(unreadCount)
            .help(feed.lastFailureMessage ?? feed.displayTitle)
        }
        .draggable(FeedReference(feedID: feed.id))
        .contextMenu {
            if let url = feed.homePageURL {
                Link(destination: url) {
                    Text("Open Website", comment: "Feed action")
                }
                Divider()
            }

            if feed.folder != nil {
                Button {
                    library.move(feed, to: nil)
                } label: {
                    Text("Move Out of Folder", comment: "Feed action")
                }
                Divider()
            }

            Button(role: .destructive) {
                library.feedPendingDeletion = feed
            } label: {
                Text("Delete", comment: "Unsubscribe from a feed")
            }
        }
    }
}

// MARK: - Empty State

/// Sits where the subscription tree will be.
///
/// Deliberately a row rather than an overlay: an overlay covers the built-in
/// streams, which are the part of the sidebar that still works when you have no
/// feeds yet.
private struct NoSubscriptionsRow: View {

    @Binding var isPresentingSubscribeSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing subscribed yet.", comment: "Sidebar empty state")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                isPresentingSubscribeSheet = true
            } label: {
                Text("Add Feed…", comment: "Subscribe to a feed")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .selectionDisabled()
    }
}

// MARK: - Sorting

extension Array where Element == Feed {

    /// Feeds in the order a person would look for them.
    ///
    /// `localizedStandardCompare` is what Finder uses: case-insensitive, so
    /// `iOS Dev Weekly` sits between `Fatbobman's` and `Matt` rather than after
    /// every capitalised name, and numerically aware, so `Issue 9` precedes
    /// `Issue 10`.
    var sortedByTitle: [Feed] {
        sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }
}
