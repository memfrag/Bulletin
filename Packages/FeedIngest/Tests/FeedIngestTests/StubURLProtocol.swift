//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Synchronization

/// A `URLProtocol` that answers from a handler instead of the network.
///
/// Conditional GET is only worth having if it demonstrably sends the right
/// headers and reacts to a 304, and neither can be checked against a real
/// server without flakiness.
final class StubURLProtocol: URLProtocol {

    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    private struct State {
        var handler: Handler?
        var requests: [URLRequest] = []
    }

    private static let state = Mutex(State())

    /// Installs a handler and returns a session wired to use it.
    static func session(handler: @escaping Handler) -> URLSession {
        state.withLock {
            $0.handler = handler
            $0.requests = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Every request the session made, in order.
    static var recordedRequests: [URLRequest] {
        state.withLock { $0.requests }
    }

    static func reset() {
        state.withLock {
            $0.handler = nil
            $0.requests = []
        }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.state.withLock { state -> Handler? in
            state.requests.append(request)
            return state.handler
        }

        guard let handler else {
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

// MARK: - Convenience

extension HTTPURLResponse {

    static func stub(
        url: URL,
        status: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
