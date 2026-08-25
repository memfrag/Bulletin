//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A node in an OPML subscription list.
///
/// OPML nests arbitrarily, which is the reason the app's folder tree does too:
/// a flat folder model would silently flatten everyone's imported hierarchy.
public struct OPMLOutline: Sendable, Equatable {

    /// The `text` attribute, which is what readers display.
    public var text: String

    /// The feed URL. `nil` means this outline is a folder.
    public var xmlURL: URL?

    /// The site the feed belongs to.
    public var htmlURL: URL?

    public var children: [OPMLOutline]

    public var isFolder: Bool { xmlURL == nil }

    public init(text: String, xmlURL: URL? = nil, htmlURL: URL? = nil, children: [OPMLOutline] = []) {
        self.text = text
        self.xmlURL = xmlURL
        self.htmlURL = htmlURL
        self.children = children
    }
}

/// A subscription list.
public struct OPMLDocument: Sendable, Equatable {

    public var title: String
    public var outlines: [OPMLOutline]

    public init(title: String, outlines: [OPMLOutline]) {
        self.title = title
        self.outlines = outlines
    }

    /// Every feed in the document, paired with the folder path it sits under.
    ///
    /// The path is what import turns back into nested folders.
    public var feeds: [(path: [String], outline: OPMLOutline)] {
        Self.flatten(outlines, path: [])
    }

    private static func flatten(_ outlines: [OPMLOutline], path: [String]) -> [(path: [String], outline: OPMLOutline)] {
        outlines.flatMap { outline -> [(path: [String], outline: OPMLOutline)] in
            if outline.isFolder {
                return flatten(outline.children, path: path + [outline.text])
            } else {
                return [(path, outline)]
            }
        }
    }
}

// MARK: - Reading

public enum OPMLReader {

    public static func read(_ data: Data) throws -> OPMLDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw FeedParsingError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }

        return OPMLDocument(title: delegate.title, outlines: delegate.roots)
    }

    private final class Delegate: NSObject, XMLParserDelegate {

        var title = ""
        var roots: [OPMLOutline] = []

        /// Outlines currently open, innermost last. An outline is only attached
        /// to its parent once it closes, because its children arrive first.
        private var stack: [OPMLOutline] = []
        private var isInTitle = false
        private var titleBuffer = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            switch elementName.lowercased() {
            case "title":
                isInTitle = true
                titleBuffer = ""

            case "outline":
                // `text` is the spec'd attribute; `title` is what some exporters
                // write instead, so accept either.
                let text = attributes["text"] ?? attributes["title"] ?? ""
                let xmlURL = (attributes["xmlUrl"] ?? attributes["xmlURL"]).flatMap(URL.init(string:))
                let htmlURL = (attributes["htmlUrl"] ?? attributes["htmlURL"]).flatMap(URL.init(string:))
                stack.append(OPMLOutline(text: text, xmlURL: xmlURL, htmlURL: htmlURL))

            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isInTitle { titleBuffer += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            switch elementName.lowercased() {
            case "title":
                if isInTitle, title.isEmpty {
                    title = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                isInTitle = false

            case "outline":
                guard let finished = stack.popLast() else { return }
                if stack.isEmpty {
                    roots.append(finished)
                } else {
                    stack[stack.count - 1].children.append(finished)
                }

            default:
                break
            }
        }
    }
}

// MARK: - Writing

public enum OPMLWriter {

    public static func write(_ document: OPMLDocument) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escape(document.title))</title>
          </head>
          <body>

        """
        for outline in document.outlines {
            xml += render(outline, indent: 4)
        }
        xml += """
          </body>
        </opml>

        """
        return xml
    }

    private static func render(_ outline: OPMLOutline, indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)

        if outline.isFolder {
            guard !outline.children.isEmpty else {
                return "\(pad)<outline text=\"\(escape(outline.text))\"/>\n"
            }
            var xml = "\(pad)<outline text=\"\(escape(outline.text))\">\n"
            for child in outline.children {
                xml += render(child, indent: indent + 2)
            }
            xml += "\(pad)</outline>\n"
            return xml
        }

        var attributes = #"type="rss" text="\#(escape(outline.text))""#
        if let xmlURL = outline.xmlURL {
            attributes += #" xmlUrl="\#(escape(xmlURL.absoluteString))""#
        }
        if let htmlURL = outline.htmlURL {
            attributes += #" htmlUrl="\#(escape(htmlURL.absoluteString))""#
        }
        return "\(pad)<outline \(attributes)/>\n"
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
