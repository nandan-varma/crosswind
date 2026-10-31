// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Catalog index")
struct CatalogIndexTests {
    private static func app(_ id: String, name: String, summary: String = "", keywords: [String] = [],
                            categories: [String] = [], description: String = "") -> CatalogApp {
        var app = CatalogApp()
        app.id = id
        app.name = name
        app.summary = summary
        app.keywords = keywords
        app.categories = categories
        app.description = description
        return app
    }

    @Test("exact name outranks prefix, word, summary and description matches")
    func rankingTiers() {
        let index = CatalogIndex(apps: [
            Self.app("a.Description", name: "Alpha", description: "works with darktable files"),
            Self.app("b.Summary", name: "Beta", summary: "A darktable companion"),
            Self.app("c.Word", name: "Gamma darktable"),
            Self.app("d.Prefix", name: "Darktable Viewer"),
            Self.app("e.Exact", name: "darktable"),
        ])
        #expect(index.search("darktable").map(\.id) == [
            "e.Exact", "d.Prefix", "c.Word", "b.Summary", "a.Description",
        ])
    }

    @Test("matches keywords and IDs")
    func keywordsAndID() {
        let index = CatalogIndex(apps: [
            Self.app("org.example.Tool", name: "Tool", keywords: ["spreadsheet"]),
            Self.app("org.other.Plain", name: "Plain"),
        ])
        #expect(index.search("spreadsheet").map(\.id) == ["org.example.Tool"])
        #expect(index.search("example").map(\.id) == ["org.example.Tool"])
    }

    @Test("case and diacritics are ignored")
    func folding() {
        let index = CatalogIndex(apps: [Self.app("org.example.Foto", name: "Fotografía Pro")])
        #expect(index.search("FOTOGRAFIA").map(\.id) == ["org.example.Foto"])
        #expect(index.search("fotografía pro").map(\.id) == ["org.example.Foto"])
    }

    @Test("every word of a multi-word query must match")
    func multiWord() {
        let index = CatalogIndex(apps: [
            Self.app("a.Dark", name: "Dark Room"),
            Self.app("b.Dark", name: "Dark Matter"),
        ])
        #expect(index.search("dark room").map(\.id) == ["a.Dark"])
        #expect(index.search("dark nothing").isEmpty)
        #expect(index.search("   ").isEmpty)
    }

    @Test("popularity breaks ties within a rank")
    func popularityTiebreak() {
        let index = CatalogIndex(apps: [
            Self.app("a.Quiet", name: "Dark Alpha"),
            Self.app("b.Busy", name: "Dark Beta"),
        ])
        #expect(index.search("dark").map(\.id) == ["a.Quiet", "b.Busy"])
        #expect(index.search("dark", popularity: ["b.Busy": 500]).map(\.id) == ["b.Busy", "a.Quiet"])
    }

    @Test("categories are counted and filtered from the AppStream main categories")
    func categories() throws {
        let index = CatalogIndex(apps: try CatalogFixtures.sampleApps())
        let counts = index.categoryCounts()
        #expect(counts.map(\.category) == CatalogCategory.allCases)
        let graphics = try #require(counts.first { $0.category == .graphics })
        #expect(graphics.count == index.apps(in: .graphics).count)
        #expect(index.apps(in: .graphics).contains { $0.id == "org.darktable.Darktable" })
        #expect(index.apps(in: .game).isEmpty)
    }

    @Test("searches the real sample catalog")
    func sampleSearch() throws {
        let index = CatalogIndex(apps: try CatalogFixtures.sampleApps())
        #expect(index.search("darktable").first?.id == "org.darktable.Darktable")
        #expect(index.search("jan").first?.id == "ai.jan.Jan")
        #expect(index.search("raw").first?.id == "org.darktable.Darktable")
    }
}
