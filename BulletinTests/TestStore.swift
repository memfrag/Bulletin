//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Synchronization
@testable import Bulletin

/// An in-memory pair of stores, so tests never touch the user's data and never
/// leak state between cases.
@MainActor
enum TestStore {

    static func makeContext() throws -> ModelContext {
        let container = try BulletinModelContainer.make(inMemory: true)
        return ModelContext(container)
    }
}

/// Serves canned responses so ingest can be exercised without a network.
///
/// - Note: `nonisolated` because `URLProtocol` is called from URLSession's own
///   queues, and this target defaults to MainActor isolation.
nonisolated final class TestURLProtocol: URLProtocol {

    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    private static let handler = Mutex<Handler?>(nil)

    static func session(handler: @escaping Handler) -> URLSession {
        Self.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        handler.withLock { $0 = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler.withLock({ $0 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Sample documents

nonisolated enum SampleFeed {

    /// An RSS feed with `count` items, so a second fetch can add items to an
    /// existing subscription.
    static func rss(itemCount: Int, startingAt start: Int = 1) -> Data {
        let items = (start..<(start + itemCount)).map { index in
            """
              <item>
                <title>Post \(index)</title>
                <link>https://example.com/posts/\(index)?utm_source=rss</link>
                <guid isPermaLink="false">post-\(index)</guid>
                <description>Summary of post \(index).</description>
                <pubDate>Mon, 03 Aug 2026 09:0\(index % 10):00 +0000</pubDate>
              </item>
            """
        }.joined(separator: "\n")

        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Example Blog</title>
            <link>https://example.com/</link>
        \(items)
          </channel>
        </rss>
        """.utf8)
    }

    static let opml = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head><title>My Subscriptions</title></head>
      <body>
        <outline text="Dev">
          <outline text="Swift">
            <outline type="rss" text="Swift by Sundell" xmlUrl="https://swiftbysundell.com/rss"/>
          </outline>
          <outline type="rss" text="Daring Fireball" xmlUrl="https://daringfireball.net/feeds/main"/>
        </outline>
        <outline type="rss" text="Root Level Feed" xmlUrl="https://example.com/feed.xml"/>
      </body>
    </opml>
    """.utf8)
}
