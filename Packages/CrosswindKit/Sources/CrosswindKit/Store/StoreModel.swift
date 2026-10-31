// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

/// An install, update or uninstall in flight for one app.
public struct AppOperation: Sendable, Equatable {
    public enum Kind: Sendable { case install, update, uninstall }
    public var kind: Kind
    public var fraction: Double
    public var detail: String
    public var failure: String?
}

/// Everything the store UI shows and does. One instance per store window; it owns the connection to the agent.
@MainActor
@Observable
public final class StoreModel {
    public enum Phase: Equatable {
        case connecting
        case installingImage(Double)
        case startingEnvironment
        case loadingCatalog
        case ready
        case failed(String)
    }

    public private(set) var phase = Phase.connecting
    public private(set) var environment = Crosswind_Agent_State()
    public private(set) var catalog = CatalogIndex(apps: [])
    public private(set) var popularity: [String: Double] = [:]
    public private(set) var trending: [String: Double] = [:]
    public private(set) var installed: [String: Crosswind_Control_InstalledApp] = [:]
    public private(set) var operations: [String: AppOperation] = [:]

    private let manifest: GuestImageManifest?
    private let imageStore: ImageStore
    private let stubs: StubInstaller
    private let opener: @MainActor (URL) async throws -> Void
    private let api: FlathubAPI
    private let cache: URL
    private var agent: AgentClient?

    /// `opener` launches a stub bundle (NSWorkspace in the app; a fake in tests).
    public init(
        manifest: GuestImageManifest?, paths: GuestPaths, stubs: StubInstaller, api: FlathubAPI = FlathubAPI(),
        opener: @escaping @MainActor (URL) async throws -> Void
    ) {
        self.manifest = manifest
        self.imageStore = ImageStore(paths: paths)
        self.stubs = stubs
        self.api = api
        self.opener = opener
        self.cache = paths.supportDirectory.appending(path: "Catalog", directoryHint: .isDirectory)
    }

    // MARK: Lifecycle

    /// Connects, installs the guest image if needed, boots the environment and loads the catalog.
    public func start() async {
        do {
            let agent = try await AgentClient.connect(role: .store)
            self.agent = agent
            observe(agent)
            try await ensureImage()
            phase = .startingEnvironment
            _ = try await agent.command(.startVm(.init()))
            phase = .loadingCatalog
            await loadCatalog(agent)
            phase = .ready
            await refreshInstalled()
            Task { await loadPopularity() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func ensureImage() async throws {
        guard let manifest else { return }
        if await imageStore.installedVersion() == manifest.version { return }
        phase = .installingImage(0)
        try await imageStore.install(manifest) { [weak self] fraction in
            Task { @MainActor in self?.phase = .installingImage(fraction) }
        }
    }

    private func observe(_ agent: AgentClient) {
        Task { [weak self] in
            for await state in agent.states { self?.environment = state }
        }
        Task { [weak self] in
            for await event in agent.control.events {
                guard case .appExited = event else { continue }
                _ = self  // running state arrives through `environment.runningApps`
            }
        }
    }

    // MARK: Catalog

    private var catalogFile: URL { cache.appending(path: "appstream.xml.gz") }

    private func loadCatalog(_ agent: AgentClient) async {
        if let data = try? Data(contentsOf: catalogFile) { await parse(data) }
        // Refresh from Flathub through the guest (signature-verified), then re-read.
        do {
            try await agent.control.refreshCatalog()
            let data = try await agent.control.catalog()
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try? data.write(to: catalogFile)
            await parse(data)
        } catch {
            if catalog.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    private func parse(_ data: Data) async {
        let index = await Task.detached(priority: .userInitiated) {
            (try? AppStreamParser.parse(gzipped: data)).map(CatalogIndex.init(apps:))
        }.value
        if let index { catalog = index }
    }

    private func loadPopularity() async {
        async let popular = try? api.popularityScores(.popular)
        async let hot = try? api.popularityScores(.trending)
        popularity = await popular ?? [:]
        trending = await hot ?? [:]
    }

    /// Test seam: sets state without an agent connection or network.
    func seed(
        catalog: CatalogIndex? = nil, popularity: [String: Double]? = nil, trending: [String: Double]? = nil,
        installed: [String: Crosswind_Control_InstalledApp]? = nil
    ) {
        if let catalog { self.catalog = catalog }
        if let popularity { self.popularity = popularity }
        if let trending { self.trending = trending }
        if let installed { self.installed = installed }
    }

    // MARK: Queries

    public func app(_ id: String) -> CatalogApp? { catalog.app(id: id) }

    public func search(_ query: String) -> [CatalogApp] { catalog.search(query, popularity: popularity) }

    public func apps(in category: CatalogCategory) -> [CatalogApp] {
        catalog.apps(in: category, popularity: popularity)
    }

    /// Most installed apps first.
    public func popular(limit: Int = 24) -> [CatalogApp] {
        popularity.sorted { $0.value > $1.value }.compactMap { catalog.app(id: $0.key) }.prefix(limit).map { $0 }
    }

    public func trendingApps(limit: Int = 12) -> [CatalogApp] {
        trending.sorted { $0.value > $1.value }.compactMap { catalog.app(id: $0.key) }.prefix(limit).map { $0 }
    }

    public var installedApps: [CatalogApp] {
        installed.keys.sorted().compactMap { catalog.app(id: $0) }
    }

    public var updatableApps: [String] {
        installed.values.filter(\.updateAvailable).map(\.appID).sorted()
    }

    public func isRunning(_ appID: String) -> Bool { environment.runningApps.contains(appID) }

    // MARK: Actions

    public func install(_ appID: String) async { await run(appID, .install) { try await $0.install(appID: appID) } }

    public func update(_ appID: String) async { await run(appID, .update) { try await $0.update(appID: appID) } }

    public func updateAll() async { await run("", .update) { try await $0.update() } }

    public func uninstall(_ appID: String, deleteData: Bool = false) async {
        await run(appID, .uninstall) { try await $0.uninstall(appID: appID, deleteData: deleteData) }
        if installed[appID] == nil { try? stubs.remove(appID: appID) }
    }

    /// Creates the app's stub on first use, then opens it; the stub starts the app and hosts its windows.
    public func open(_ appID: String) async {
        let name = app(appID)?.name ?? installed[appID]?.name ?? appID
        do {
            let version = installed[appID]?.version ?? "1"
            let bundle: URL
            if let existing = stubs.bundleURL(for: appID) {
                bundle = existing
            } else {
                // The icon is optional: a failed download or undecodable image installs the stub without one.
                var iconPNG: Data?
                if let icon = app(appID)?.icons.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                    var request = URLRequest(url: icon.url)
                    request.timeoutInterval = 10
                    iconPNG = try? await URLSession.shared.data(for: request).0
                }
                do {
                    bundle = try stubs.install(appID: appID, name: name, version: version, iconPNG: iconPNG)
                } catch where iconPNG != nil {
                    bundle = try stubs.install(appID: appID, name: name, version: version, iconPNG: nil)
                }
            }
            try await opener(bundle)
        } catch {
            operations[appID] = AppOperation(kind: .install, fraction: 0, detail: "", failure: error.localizedDescription)
        }
    }

    public func clearFailure(_ appID: String) {
        if operations[appID]?.failure != nil { operations[appID] = nil }
    }

    private func run(
        _ appID: String, _ kind: AppOperation.Kind, _ start: (GuestControl) async throws -> OperationHandle
    ) async {
        guard let control = agent?.control else { return }
        operations[appID] = AppOperation(kind: kind, fraction: 0, detail: "")
        do {
            let handle = try await start(control)
            Task { [weak self] in
                for await progress in handle.progress {
                    self?.operations[appID]?.fraction = Double(progress.percent) / 100
                    self?.operations[appID]?.detail = progress.detail
                }
            }
            try await handle.result()
            operations[appID] = nil
        } catch {
            operations[appID] = AppOperation(kind: kind, fraction: 0, detail: "", failure: error.localizedDescription)
        }
        await refreshInstalled()
    }

    public func refreshInstalled() async {
        guard let list = try? await agent?.control.installed() else { return }
        installed = Dictionary(uniqueKeysWithValues: list.map { ($0.appID, $0) })
    }
}
