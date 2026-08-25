//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Testing

enum Fixture {

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func string(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}
