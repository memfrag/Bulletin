//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing
@testable import Bulletin

/// The app is unsandboxed and ships no Share Extension, so a `bulletin://` link
/// and the Services menu are the whole of "subscribe from Safari". Both hand
/// over text a person wrote, which is to say text in whatever shape they liked.
@MainActor
@Suite("Subscription inbox", .serialized)
struct SubscriptionInboxTests {

    private var inbox: SubscriptionInbox {
        let inbox = SubscriptionInbox.shared
        _ = inbox.take()  // clear anything a previous test left
        return inbox
    }

    @Test("The explicit form is understood")
    func handlesQueryForm() throws {
        let inbox = inbox
        inbox.handle(URL(string: "bulletin://subscribe?url=https://example.com/feed.xml")!)

        #expect(inbox.take() == URL(string: "https://example.com/feed.xml"))
    }

    @Test("The short form is understood too, because people will write it")
    func handlesShortForm() throws {
        let inbox = inbox
        inbox.handle(URL(string: "bulletin://example.com/feed.xml")!)

        #expect(inbox.take() == URL(string: "https://example.com/feed.xml"))
    }

    @Test("A URL from another scheme is ignored")
    func ignoresOtherSchemes() throws {
        let inbox = inbox
        inbox.handle(URL(string: "https://example.com/feed.xml")!)

        // Anything else arriving through `onOpenURL` is not ours to act on.
        #expect(inbox.take() == nil)
    }

    @Test("Text from the Services menu is accepted with or without a scheme")
    func handlesServiceText() throws {
        let inbox = inbox
        inbox.handle(text: "https://example.com/feed.xml")
        #expect(inbox.take() == URL(string: "https://example.com/feed.xml"))

        // Selecting a bare domain in a page and choosing the service is a
        // perfectly reasonable thing to do.
        inbox.handle(text: "  example.com  ")
        #expect(inbox.take() == URL(string: "https://example.com"))
    }

    @Test("Empty text leaves nothing pending")
    func ignoresEmptyText() throws {
        let inbox = inbox
        inbox.handle(text: "   ")

        #expect(inbox.take() == nil)
    }

    @Test("Taking a URL clears it")
    func takeClearsPending() throws {
        let inbox = inbox
        inbox.handle(text: "example.com")

        #expect(inbox.take() != nil)
        // Otherwise the subscribe sheet would reopen with the same URL every
        // time it appeared.
        #expect(inbox.take() == nil)
    }
}
