// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

enum CatalogFixtures {
    static func data(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func sampleApps() throws -> [CatalogApp] {
        try AppStreamParser.parse(xml: data("appstream-sample", "xml"))
    }
}
