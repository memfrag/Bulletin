//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {

    /// OPML, which macOS does not know about on its own.
    ///
    /// Declared with `importedAs:` rather than `exportedAs:` because the format
    /// is not ours — `org.opml` is somebody else's reverse-DNS name, and
    /// claiming to define it is what produced the runtime complaint that this
    /// type "was expected to be declared and exported".
    ///
    /// The matching `UTImportedTypeDeclarations` entry in `Info.plist` is what
    /// actually maps the `.opml` extension. Without it the system types those
    /// files as an anonymous `dyn.…` conforming only to `public.data`, so they
    /// match neither this type nor `.xml` and the open panel greys them out.
    ///
    /// - Note: `nonisolated` so that `FileDocument`, which is used off the main
    ///   actor, can reference it.
    nonisolated static let opml = UTType(importedAs: "org.opml.opml", conformingTo: .xml)
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
