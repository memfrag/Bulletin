//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

enum Fixture {

    static func html(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
            throw FixtureError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}
