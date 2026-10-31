// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum HarnessError: Error, CustomStringConvertible {
    case emptyCatalog
    case unknownSet(String)

    public var description: String {
        switch self {
        case .emptyCatalog: "the Flathub catalog is empty; run `crosswindctl catalog refresh` first"
        case .unknownSet(let name): "unknown set \"\(name)\" (known: curated)"
        }
    }
}

/// Installs Flathub apps, launches each through a headless stub and records what works.
public enum CompatHarness {
    /// The first batch: one or two apps per toolkit family (see docs/research/x11-apps.md).
    public static let curatedSet = [
        "org.gnome.Calculator", "org.gnome.TextEditor", "org.gnome.clocks",  // GTK4
        "org.kde.kcalc", "org.kde.kate",  // Qt
        "com.vscodium.codium",  // Electron
        "org.videolan.VLC", "org.audacityteam.Audacity",  // X11
        "org.gnome.gedit", "org.gimp.GIMP",  // GTK3
        "org.mozilla.firefox",  // browser
    ]

    public struct Options: Sendable {
        /// How long to wait for a window, a first frame, and an exit after close.
        public var timeout: Duration = .seconds(90)
        public var keepInstalled = false
        public var imageVersion = "dev"
        public var screenshotDirectory: URL

        public init(screenshotDirectory: URL) {
            self.screenshotDirectory = screenshotDirectory
        }
    }

    /// Everything one app's test needs besides its own report.
    struct Session: Sendable {
        let control: AgentClient
        let events: EventLog
        let options: Options
        let log: @Sendable (String) -> Void
    }

    /// Runs the apps one after another. `control` is a connected `ctl` client with the VM running.
    /// `onRecord` is called as each app finishes.
    public static func run(
        ids: [String], control: AgentClient, options: Options, log: @escaping @Sendable (String) -> Void,
        onRecord: @escaping @Sendable (CompatRecord) -> Void = { _ in }
    ) async throws -> [CompatRecord] {
        let catalog = try AppStreamParser.parse(gzipped: try await control.control.catalog())
        guard !catalog.isEmpty else { throw HarnessError.emptyCatalog }
        // AppStream ids of some apps carry a ".desktop" suffix (org.kde.kcalc.desktop); Flatpak ids do not.
        var apps: [String: CatalogApp] = [:]
        for app in catalog {
            apps[app.id] = apps[app.id] ?? app
            if app.id.hasSuffix(".desktop") {
                let flatpakID = String(app.id.dropLast(".desktop".count))
                apps[flatpakID] = apps[flatpakID] ?? app
            }
        }

        let events = EventLog()
        let pump = Task { for await event in control.control.events { await events.record(event) } }
        defer { pump.cancel() }

        let session = Session(control: control, events: events, options: options, log: log)
        var records: [CompatRecord] = []
        for appID in ids.reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
            log("== \(appID)")
            let record = await test(appID, apps: apps, session: session)
            log("   \(record.status.title)")
            records.append(record)
            onRecord(record)
        }
        return records
    }

    private static func test(_ appID: String, apps: [String: CatalogApp], session: Session) async -> CompatRecord {
        var report = Report(appID: appID, name: apps[appID]?.name ?? appID, options: session.options)
        guard apps[appID] != nil else {
            report.notes.append("not in the Flathub catalog")
            return report.finish(status: .noArmBuild)
        }
        do {
            try await ensureInstalled(appID, control: session.control, log: session.log)
            report.appVersion = try await session.control.control.installed().first { $0.appID == appID }?.version ?? ""
        } catch {
            let text = String(describing: error).lowercased()
            let missing = ["no remote refs", "not found", "couldn't find", "no such ref", "no entry for"]
                .contains { text.contains($0) }
            report.notes.append("install failed: \(error)")
            return report.finish(status: missing ? .noArmBuild : .untested)
        }

        var forced: CompatStatus?
        do {
            try await exercise(appID, report: &report, session: session)
        } catch {
            report.notes.append("harness error: \(error)")
            forced = .untested
        }
        if !session.options.keepInstalled {
            do {
                let handle = try await session.control.control.uninstall(appID: appID, deleteData: true)
                try await handle.result()
            } catch {
                report.notes.append("uninstall failed: \(error)")
            }
        }
        let lines = await session.events.lines(appID)
        if lines.contains(where: { $0.lowercased().contains("cannot open display") || $0.contains("Unable to init") }) {
            report.checks.needsX11 = true
        }
        return report.finish(status: forced, logs: lines)
    }

    private static func ensureInstalled(
        _ appID: String, control: AgentClient, log: @escaping @Sendable (String) -> Void
    ) async throws {
        if try await control.control.installed().contains(where: { $0.appID == appID }) { return }
        let handle = try await control.control.install(appID: appID)
        let progress = Task {
            var last = -1
            for await update in handle.progress where Int(update.percent) != last {
                last = Int(update.percent)
                log("   \(update.phase) \(update.percent)% \(update.detail)")
            }
        }
        defer { progress.cancel() }
        try await handle.result()
    }

    /// Polls `condition` every 100 ms until it holds or `timeout` passes.
    static func poll(_ timeout: Duration, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if await condition() { return true }
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Accumulates one app's result.
    struct Report {
        let appID: String
        let name: String
        let options: Options
        var checks = CompatChecks()
        var notes: [String] = []
        var appVersion = ""
        var screenshot: String?

        init(appID: String, name: String, options: Options) {
            self.appID = appID
            self.name = name
            self.options = options
        }

        /// Builds the record. With no status, the status comes from the checks. The failure notes are followed by
        /// the first guest log lines whenever the app is not fully working.
        @discardableResult
        mutating func finish(status: CompatStatus?, logs: [String] = []) -> CompatRecord {
            let resolved = status ?? CompatClassifier.status(for: checks)
            if resolved != .works { notes += logs.prefix(200) }
            return CompatRecord(
                appID: appID, name: name, status: resolved, checks: checks, notes: notes, testedAt: Date(),
                guestImageVersion: options.imageVersion, appVersion: appVersion, arch: hostArch,
                screenshot: screenshot)
        }
    }

    static var hostArch: String {
        #if arch(arm64)
            "aarch64"
        #else
            "x86_64"
        #endif
    }
}

/// Guest events by app: exit codes and log lines (at most 200 per app).
actor EventLog {
    private var appByLaunch: [String: String] = [:]
    private var logs: [String: [String]] = [:]
    private var exits: [String: Int32] = [:]

    func record(_ event: GuestControl.Event) {
        switch event {
        case .appStarted(let started):
            appByLaunch[started.launchID] = started.appID
        case .appExited(let exited):
            exits[exited.appID] = exited.exitCode
        case .log(let line):
            let app = appByLaunch[line.launchID] ?? line.source
            if (logs[app]?.count ?? 0) < 200 { logs[app, default: []].append("[\(line.source)] \(line.text)") }
        }
    }

    func exitCode(_ appID: String) -> Int32? { exits[appID] }
    func lines(_ appID: String) -> [String] { logs[appID] ?? [] }
}
