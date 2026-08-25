//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {

    /// OPML has no registered system type, so it is declared here by filename
    /// extension and treated as XML.
    ///
    /// - Note: `nonisolated` so that `FileDocument`, which is used off the main
    ///   actor, can reference it.
    nonisolated static let opml = UTType(exportedAs: "org.opml.opml", conformingTo: .xml)
}

/// A subscription list on its way to disk.
///
/// - Note: `nonisolated` because `FileDocument` is read and written off the
///   main actor, and this app defaults to MainActor isolation.
nonisolated struct OPMLFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.opml, .xml] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
