//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Bulletin", category: "OPML")

extension View {

    /// Presents the OPML import panel.
    ///
    /// Importing is how anyone arrives here from another reader, so it accepts
    /// both the OPML type and plain XML — plenty of exporters write `.xml`.
    func opmlFileImporter(isPresented: Binding<Bool>) -> some View {
        modifier(OPMLImporter(isPresented: isPresented))
    }

    /// Presents the OPML export panel.
    func opmlFileExporter(isPresented: Binding<Bool>) -> some View {
        modifier(OPMLExporter(isPresented: isPresented))
    }
}

// MARK: - Import

private struct OPMLImporter: ViewModifier {

    @Environment(Library.self) private var library

    @Binding var isPresented: Bool

    @State private var result: FeedStore.OPMLImportResult?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.opml, .xml],
                allowsMultipleSelection: false
            ) { outcome in
                switch outcome {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        result = try library.importOPML(at: url)
                    } catch {
                        errorMessage = error.localizedDescription
                        log.error("OPML import failed: \(error.localizedDescription, privacy: .public)")
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert(
                Text("Import Complete", comment: "OPML import result title"),
                isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }),
                presenting: result
            ) { _ in
                Button(role: .close) {} label: {
                    Text("OK", comment: "Dismiss")
                }
            } message: { result in
                Text(
                    "Added \(result.importedFeedCount) feeds in \(result.createdFolderCount) folders. \(result.alreadySubscribedCount) were already subscribed.",
                    comment: "OPML import result detail"
                )
            }
            .alert(
                Text("Import Failed", comment: "OPML import error title"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                presenting: errorMessage
            ) { _ in
                Button(role: .close) {} label: {
                    Text("OK", comment: "Dismiss")
                }
            } message: { message in
                Text(message)
            }
    }
}

// MARK: - Export

private struct OPMLExporter: ViewModifier {

    @Environment(Library.self) private var library

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $isPresented,
                document: OPMLFileDocument(text: (try? library.exportOPML()) ?? ""),
                contentType: .opml,
                defaultFilename: "Bulletin Subscriptions"
            ) { outcome in
                if case .failure(let error) = outcome {
                    log.error("OPML export failed: \(error.localizedDescription, privacy: .public)")
                }
            }
    }
}
