//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Parses RSS 1.0, the RDF-based flavour.
///
/// FeedKit dropped this format in 10.x, and it is still emitted by long-lived
/// blogs and academic sites, so it is parsed here instead.
///
/// The shape is unlike RSS 2.0 in one structural way that matters: `<item>`
/// elements are siblings of `<channel>`, not children of it. The channel holds
/// only an ordered list of item references.
///
/// Dates arrive as `dc:date` in W3CDTF, which is a profile of ISO 8601.
///
enum RDFFeedParser {

    static func parse(_ data: Data) throws -> ParsedFeed {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            throw FeedParsingError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }

        return ParsedFeed(
            format: .rdf,
            title: HTMLEntities.decode(delegate.channelTitle.trimmed),
            homePageURL: URL(string: delegate.channelLink.trimmed),
            items: delegate.items.map(\.parsed)
        )
    }

    // MARK: - Delegate

    private final class Delegate: NSObject, XMLParserDelegate {

        struct Item {
            var about: String = ""
            var title: String = ""
            var link: String = ""
            var description: String = ""
            var creator: String = ""
            var date: String = ""

            var parsed: ParsedFeedItem {
                let url = URL(string: link.trimmed)
                // `rdf:about` is the canonical per-item identity in RSS 1.0 and
                // is normally the item URL. Fall back to the link, then to the
                // title, so an item is never dropped for lacking an id.
                let guid = about.trimmed.isEmpty ? (link.trimmed.isEmpty ? title.trimmed : link.trimmed) : about.trimmed
                return ParsedFeedItem(
                    guid: guid,
                    title: HTMLEntities.decode(title.trimmed),
                    author: creator.trimmed.nilIfEmpty.map(HTMLEntities.decode),
                    url: url,
                    contentHTML: description.trimmed.nilIfEmpty,
                    publishedAt: W3CDateFormatter.date(from: date.trimmed)
                )
            }
        }

        private enum Scope {
            case none
            case channel
            case item
        }

        var channelTitle = ""
        var channelLink = ""
        var items: [Item] = []

        private var scope: Scope = .none
        private var currentElement = ""
        private var buffer = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            currentElement = elementName.localName
            buffer = ""

            switch currentElement {
            case "channel":
                scope = .channel
            case "item":
                scope = .item
                var item = Item()
                item.about = attributes["rdf:about"] ?? attributes["about"] ?? ""
                items.append(item)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            buffer += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let name = elementName.localName
            defer { buffer = "" }

            if name == "channel" || name == "item" {
                scope = .none
                return
            }

            switch scope {
            case .channel:
                switch name {
                case "title": channelTitle += buffer
                case "link": channelLink += buffer
                default: break
                }

            case .item:
                guard !items.isEmpty else { return }
                switch name {
                case "title": items[items.count - 1].title += buffer
                case "link": items[items.count - 1].link += buffer
                case "description": items[items.count - 1].description += buffer
                case "creator": items[items.count - 1].creator += buffer
                case "date": items[items.count - 1].date += buffer
                default: break
                }

            case .none:
                break
            }
        }
    }
}

// MARK: - Helpers

private extension String {

    /// The element name without its namespace prefix.
    ///
    /// Namespace processing is off because RSS 1.0 puts its core elements in a
    /// default namespace and its dates in Dublin Core, and matching on the
    /// local name is both simpler and more forgiving of feeds that declare
    /// their prefixes unusually.
    var localName: String {
        guard let colon = lastIndex(of: ":") else { return self }
        return String(self[index(after: colon)...])
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
