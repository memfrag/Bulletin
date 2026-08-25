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

    @Query(filter: #Predicate<Feed> { $0.folder == nil }, sort: \Feed.title)
    private var rootFeeds: [Feed]

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

                Section(header: Text("Subscriptions", comment: "Sidebar section of feeds and folders")) {
                    if rootFolders.isEmpty && rootFeeds.isEmpty {
                        NoSubscriptionsRow(
                            isPresentingSubscribeSheet: $library.isPresentingSubscribeSheet
                        )
                    } else {
                        ForEach(rootFolders) { folder in
                            FolderRow(folder: folder, counts: counts)
                        }
                        ForEach(rootFeeds) { feed in
                            FeedRow(feed: feed, unreadCount: counts[feed.id])
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 340)
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
        .opmlFileImporter(isPresented: $library.isPresentingOPMLImporter)
        .opmlFileExporter(isPresented: $library.isPresentingOPMLExporter)
    }
}

// MARK: - Folder Row

/// A folder and everything under it.
///
/// Recursive, because the folder tree is: OPML nests arbitrarily and flattening
/// it on import would quietly rearrange everyone's subscription list.
private struct FolderRow: View {

    let folder: Folder
    let counts: UnreadCounts

    var body: some View {
        DisclosureGroup {
            ForEach((folder.children ?? []).sorted { $0.sortIndex < $1.sortIndex }) { child in
                FolderRow(folder: child, counts: counts)
            }
            ForEach((folder.feeds ?? []).sorted { $0.displayTitle < $1.displayTitle }) { feed in
                FeedRow(feed: feed, unreadCount: counts[feed.id])
            }
        } label: {
            NavigationLink(value: SidebarItem.folder(folder.id)) {
                Label(folder.name, systemImage: "folder")
                    .badge(counts.count(for: folder))
            }
        }
    }
}

// MARK: - Feed Row

private struct FeedRow: View {

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
