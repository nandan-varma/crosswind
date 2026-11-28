// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The Intel (x86_64) Flathub catalog, used only for apps with no native build. They run through Rosetta.
enum IntelCatalog {
    /// Apps in the Intel catalog that `native` lacks, marked as needing Rosetta. A missing or broken catalog adds
    /// nothing.
    static func apps(_ intel: Data?, besides native: [CatalogApp]) -> [CatalogApp] {
        guard let intel, !intel.isEmpty, let apps = try? AppStreamParser.parse(gzipped: intel) else { return [] }
        let known = Set(native.map(\.id))
        return apps.filter { !known.contains($0.id) }.map {
            var app = $0
            app.requiresRosetta = true
            return app
        }
    }
}
