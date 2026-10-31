// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("AppOperation")
struct AppOperationTests {
    @Test("operations compare by every field")
    func equality() {
        let base = AppOperation(kind: .install, fraction: 0.5, detail: "Downloading", failure: nil)
        #expect(base == AppOperation(kind: .install, fraction: 0.5, detail: "Downloading", failure: nil))
        #expect(base != AppOperation(kind: .update, fraction: 0.5, detail: "Downloading", failure: nil))
        #expect(base != AppOperation(kind: .install, fraction: 0.6, detail: "Downloading", failure: nil))
        #expect(base != AppOperation(kind: .install, fraction: 0.5, detail: "Installing", failure: nil))
        #expect(base != AppOperation(kind: .install, fraction: 0.5, detail: "Downloading", failure: "boom"))
    }
}

@MainActor
@Suite("StoreModel before the agent connects")
struct StoreModelTests {
    /// Builds a model whose paths and stubs live in a temporary directory. `start()` is never called,
    /// so no Mach service, VM or network access happens.
    private func makeModel() throws -> (StoreModel, URL) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "StoreModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = GuestPaths(supportDirectory: root.appending(path: "support", directoryHint: .isDirectory))
        let stubs = StubInstaller(
            template: root.appending(path: "Template.app", directoryHint: .isDirectory),
            directory: root.appending(path: "Stubs", directoryHint: .isDirectory))
        let model = StoreModel(manifest: nil, paths: paths, stubs: stubs) { _ in }
        return (model, root)
    }

    @Test("starts in the connecting phase with an empty catalog")
    func initialState() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(model.phase == .connecting)
        #expect(model.catalog.isEmpty)
        #expect(model.popularity.isEmpty)
        #expect(model.trending.isEmpty)
        #expect(model.installed.isEmpty)
        #expect(model.operations.isEmpty)
    }

    @Test("catalog-derived queries return nothing for an empty catalog")
    func emptyQueries() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(model.app("org.darktable.Darktable") == nil)
        #expect(model.popular().isEmpty)
        #expect(model.trendingApps().isEmpty)
        #expect(model.installedApps.isEmpty)
        #expect(model.updatableApps.isEmpty)
        #expect(model.search("darktable").isEmpty)
    }

    @Test("no app is running before the agent reports state")
    func noRunningApps() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(!model.isRunning("org.darktable.Darktable"))
    }

    @Test("clearFailure leaves operations without a failure untouched")
    func clearFailureKeepsSuccessfulOperations() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }

        model.clearFailure("org.darktable.Darktable")
        #expect(model.operations.isEmpty)
    }
}

@MainActor
@Suite("StoreModel queries over a seeded catalog")
struct StoreModelQueryTests {
    private static let darktable = "org.darktable.Darktable"
    private static let jan = "ai.jan.Jan"
    private static let eduk = "br.com.eduk.school"

    private func makeModel() throws -> (StoreModel, URL) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "StoreModelQueryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = GuestPaths(supportDirectory: root.appending(path: "support", directoryHint: .isDirectory))
        let stubs = StubInstaller(
            template: root.appending(path: "Template.app", directoryHint: .isDirectory),
            directory: root.appending(path: "Stubs", directoryHint: .isDirectory))
        return (StoreModel(manifest: nil, paths: paths, stubs: stubs) { _ in }, root)
    }

    private func installed(_ id: String, _ name: String, update: Bool = false) -> Crosswind_Control_InstalledApp {
        var app = Crosswind_Control_InstalledApp()
        app.appID = id
        app.name = name
        app.version = "1.0"
        app.updateAvailable = update
        return app
    }

    private func byID(_ apps: Crosswind_Control_InstalledApp...) -> [String: Crosswind_Control_InstalledApp] {
        Dictionary(uniqueKeysWithValues: apps.map { ($0.appID, $0) })
    }

    @Test("app(_:) finds fixture apps by ID and returns nil for unknown IDs")
    func lookupByID() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()))

        #expect(model.app(Self.darktable)?.name == "darktable")
        #expect(model.app("no.such.App") == nil)
    }

    @Test("search finds apps by name and returns nothing for gibberish")
    func search() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()))

        #expect(model.search("darktable").first?.id == Self.darktable)
        #expect(model.search("qqqqqzzzzxxxx").isEmpty)
    }

    @Test("apps(in:) returns only apps in the category")
    func appsInCategory() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()))

        let graphics = model.apps(in: .graphics).map(\.id)
        #expect(graphics.contains(Self.darktable))
        #expect(!graphics.contains(Self.jan))
        #expect(model.apps(in: .graphics).allSatisfy { $0.categories.contains("Graphics") })
    }

    @Test("popular orders by popularity, drops unknown IDs, and honours the limit")
    func popular() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(
            catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()),
            popularity: [Self.eduk: 10, Self.darktable: 500, Self.jan: 900, "no.such.App": 1000])

        #expect(model.popular().map(\.id) == [Self.jan, Self.darktable, Self.eduk])
        #expect(model.popular(limit: 1).map(\.id) == [Self.jan])
    }

    @Test("trendingApps orders by trending score and honours the limit")
    func trending() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(
            catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()),
            trending: [Self.eduk: 1, Self.darktable: 3])

        #expect(model.trendingApps().map(\.id) == [Self.darktable, Self.eduk])
        #expect(model.trendingApps(limit: 1).map(\.id) == [Self.darktable])
    }

    @Test("installedApps lists installed IDs sorted, skipping any missing from the catalog")
    func installedApps() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(
            catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()),
            installed: byID(
                installed(Self.jan, "Jan"),
                installed(Self.darktable, "darktable"),
                installed("no.such.App", "Ghost")
            ))

        #expect(model.installedApps.map(\.id) == [Self.darktable, Self.jan])
    }

    @Test("updatableApps lists only installed apps with an update, sorted")
    func updatableApps() throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.seed(
            catalog: CatalogIndex(apps: try CatalogFixtures.sampleApps()),
            installed: byID(
                installed(Self.jan, "Jan", update: true),
                installed(Self.darktable, "darktable", update: true),
                installed(Self.eduk, "eduK")
            ))

        #expect(model.updatableApps == [Self.darktable, Self.jan])
    }
}
