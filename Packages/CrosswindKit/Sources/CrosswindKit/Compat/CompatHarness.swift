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

    /// Runs the apps one after another. `control` is a connected `ctl` client with the VM running.
    public static func run(
        ids: [String], control: AgentClient, options: Options, log: @escaping @Sendable (String) -> Void
    ) async throws -> [CompatRecord] {
        let catalog = try AppStreamParser.parse(gzipped: try await control.control.catalog())
        guard !catalog.isEmpty else { throw HarnessError.emptyCatalog }
        let apps = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let events = EventLog()
        let pump = Task { for await event in control.control.events { await events.record(event) } }
        defer { pump.cancel() }

        var records: [CompatRecord] = []
        for appID in ids.reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
            log("== \(appID)")
            let record = await test(appID, apps: apps, control: control, events: events, options: options, log: log)
            log("   \(record.status.title)")
            records.append(record)
        }
        return records
    }

    private static func test(
        _ appID: String, apps: [String: CatalogApp], control: AgentClient, events: EventLog, options: Options,
        log: @escaping @Sendable (String) -> Void
    ) async -> CompatRecord {
        var report = Report(appID: appID, name: apps[appID]?.name ?? appID, options: options)
        guard apps[appID] != nil else {
            report.notes.append("not in the Flathub catalog")
            return report.finish(status: .noArmBuild)
        }
        do {
            if try await control.control.installed().first(where: { $0.appID == appID }) == nil {
                try await install(appID, control: control, log: log)
            }
            report.appVersion = try await control.control.installed().first { $0.appID == appID }?.version ?? ""
        } catch {
            let text = String(describing: error).lowercased()
            let missing = ["no remote refs", "not found", "couldn't find", "no such ref", "no entry for"]
                .contains { text.contains($0) }
            report.notes.append("install failed: \(error)")
            return report.finish(status: missing ? .noArmBuild : .untested)
        }

        var forced: CompatStatus?
        do {
            try await exercise(appID, report: &report, control: control, events: events, options: options, log: log)
        } catch {
            report.notes.append("harness error: \(error)")
            forced = .untested
        }
        if !options.keepInstalled {
            do {
                let handle = try await control.control.uninstall(appID: appID, deleteData: true)
                try await handle.result()
            } catch {
                report.notes.append("uninstall failed: \(error)")
            }
        }
        let lines = await events.lines(appID)
        if lines.contains(where: { $0.lowercased().contains("cannot open display") || $0.contains("Unable to init server") }) {
            report.checks.needsX11 = true
        }
        return report.finish(status: forced, logs: lines)
    }

    private static func install(_ appID: String, control: AgentClient, log: @escaping @Sendable (String) -> Void) async throws {
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

    /// Launches the app through a stub and runs the checks. Stops at the first failed step after recording it.
    private static func exercise(
        _ appID: String, report: inout Report, control: AgentClient, events: EventLog, options: Options,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        let stub = try await AgentClient.connect(role: .stub, appID: appID)
        let display = HeadlessDisplay()
        let pump = Task {
            for await message in stub.display {
                if let reply = await display.consume(message) { await stub.send(display: reply) }
            }
        }
        defer {
            pump.cancel()
            Task { await stub.disconnect() }
        }

        do {
            _ = try await stub.command(.launchApp(.with { $0.appID = appID }))
        } catch {
            report.notes.append("launch failed: \(error)")
            report.checks.windowAppears = .fail
            return
        }
        let opened = await poll(options.timeout) { await display.toplevel != nil }
        report.checks.noCrash = await events.exitCode(appID) == nil ? .pass : .fail
        guard opened, let window = await display.toplevel else {
            report.checks.windowAppears = .fail
            report.notes.append("no window within \(options.timeout)")
            return
        }
        report.checks.windowAppears = .pass
        log("   window \(window.id) \(window.title)")

        await stub.send(display: configure(window.id))
        let rendered = await poll(options.timeout) { ((await display.primary)?.frames ?? 0) > 0 }
        guard rendered, let shot = await display.primary else {
            report.checks.renders = .fail
            report.notes.append("no frame within \(options.timeout)")
            return
        }
        try? await Task.sleep(for: .milliseconds(1500))
        guard let settled = await display.primary else { return }
        let flat = settled.canvas.isFlat
        report.checks.renders = flat ? .fail : .pass
        if flat { report.notes.append("window is one flat colour") }
        let png = options.screenshotDirectory.appending(path: "\(appID).png")
        try? settled.canvas.writePNG(to: png)
        report.screenshot = "screenshots/\(appID).png"

        let before = await display.frameCount
        let width = Double(settled.canvas.width) * 120 / Double(settled.scale120)
        let height = Double(settled.canvas.height) * 120 / Double(settled.scale120)
        for event in inputSequence(window: window.id, x: width / 2, y: height / 2) {
            await stub.send(display: event)
            try? await Task.sleep(for: .milliseconds(60))
        }
        let reacted = await poll(.seconds(2)) { await display.frameCount > before }
        report.checks.inputWorks = reacted ? .pass : .unknown

        let earlyExit = await events.exitCode(appID)
        report.checks.noCrash = earlyExit == nil ? .pass : .fail
        if earlyExit != nil {
            report.notes.append("exited before close")
            report.checks.cleanExit = .skipped
            return
        }

        await stub.send(display: close(window.id))
        if await poll(.seconds(10), { await events.exitCode(appID) != nil }) {
            report.checks.cleanExit = .pass
            return
        }
        report.checks.cleanExit = .fail
        report.notes.append("did not exit within 10 s of a close request; stopping it")
        try? await control.control.stop(appID: appID)
        _ = await poll(.seconds(10)) { await events.exitCode(appID) != nil }
        switch await events.exitCode(appID) {
        case 137?: report.notes.append("needed SIGKILL (exit 137)")
        case 143?: report.notes.append("needed SIGTERM (exit 143)")
        case let code?: report.notes.append("exit code \(code) after stop")
        case nil: report.notes.append("still running after stop")
        }
    }

    private static func configure(_ window: UInt32) -> ToGuest {
        .with {
            $0.msg = .configure(
                .with {
                    $0.window = window
                    $0.width = 1024
                    $0.height = 768
                    $0.scale120 = 240
                    $0.activated = true
                })
        }
    }

    private static func close(_ window: UInt32) -> ToGuest {
        .with { $0.msg = .close(.with { $0.window = window }) }
    }

    /// Pointer motion to the centre, a left click, then Space and Return.
    private static func inputSequence(window: UInt32, x: Double, y: Double) -> [ToGuest] {
        func input(_ event: Crosswind_Display_Input.OneOf_Event) -> ToGuest {
            .with { $0.msg = .input(.with { $0.window = window; $0.event = event }) }
        }
        return [
            input(.motion(.with { $0.x = x; $0.y = y })),
            input(.button(.with { $0.button = 0x110; $0.pressed = true })),
            input(.button(.with { $0.button = 0x110; $0.pressed = false })),
            input(.key(.with { $0.keycode = 57; $0.pressed = true })),
            input(.key(.with { $0.keycode = 57; $0.pressed = false })),
            input(.key(.with { $0.keycode = 28; $0.pressed = true })),
            input(.key(.with { $0.keycode = 28; $0.pressed = false })),
        ]
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
    private struct Report {
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

        /// Builds the record. With no status, the status comes from the checks; the failure notes are followed by
        /// the first guest log lines whenever the app is not fully working.
        @discardableResult
        mutating func finish(status: CompatStatus?, logs: [String] = []) -> CompatRecord {
            let resolved = status ?? CompatClassifier.status(for: checks)
            if resolved != .works { notes += logs.prefix(200) }
            return CompatRecord(
                appID: appID, name: name, status: resolved, checks: checks, notes: notes, testedAt: Date(),
                guestImageVersion: options.imageVersion, appVersion: appVersion, arch: hostArch, screenshot: screenshot)
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
