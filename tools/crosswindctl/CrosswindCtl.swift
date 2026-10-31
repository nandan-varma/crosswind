// SPDX-License-Identifier: AGPL-3.0-or-later
import ArgumentParser
import CrosswindKit
import Foundation

@main
struct CrosswindCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crosswindctl",
        abstract: "Control the Crosswind host agent and the Linux environment.",
        subcommands: [
            Status.self, Start.self, Stop.self, Installed.self, Install.self, Uninstall.self, Update.self,
            Launch.self, Logs.self, CatalogCommand.self, StubCommand.self, ImageCommand.self,
            Windows.self, TypeText.self, Click.self, Diagnose.self, CompatCommand.self,
        ]
    )
}

private func connect() async throws -> AgentClient {
    try await AgentClient.connect(role: .ctl)
}

private func describe(_ state: Crosswind_Agent_State) -> String {
    var text = "\(state.phase)".lowercased()
    if !state.detail.isEmpty { text += " (\(state.detail))" }
    if !state.runningApps.isEmpty { text += "; running: " + state.runningApps.joined(separator: ", ") }
    return text
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the Linux environment's state.")

    func run() async throws {
        let client = try await connect()
        for await state in client.states {
            print(describe(state))
            return
        }
    }
}

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Boot the Linux environment.")

    func run() async throws {
        print(describe(try await connect().command(.startVm(.init())).state))
    }
}

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Shut the Linux environment down.")

    func run() async throws {
        print(describe(try await connect().command(.stopVm(.init())).state))
    }
}

struct Installed: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List installed apps.")

    func run() async throws {
        let client = try await connect()
        for app in try await client.control.installed() {
            print("\(app.appID)\t\(app.version)\t\(app.name)\(app.updateAvailable ? "\tupdate available" : "")")
        }
    }
}

private func follow(_ handle: OperationHandle, verb: String) async throws {
    Task {
        for await progress in handle.progress {
            print("\r\(verb) \(progress.percent)% \(progress.detail)", terminator: "")
            fflush(stdout)
        }
    }
    try await handle.result()
    print("\r\(verb): done                                        ")
}

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Install an app from Flathub.")
    @Argument(help: "Flatpak app id, e.g. org.gnome.Calculator") var appID: String

    func run() async throws {
        let client = try await connect()
        _ = try await client.command(.startVm(.init()))
        try await follow(try await client.control.install(appID: appID), verb: "installing")
    }
}

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove an app.")
    @Argument var appID: String
    @Flag(help: "Also delete the app's data.") var deleteData = false

    func run() async throws {
        let client = try await connect()
        _ = try await client.command(.startVm(.init()))
        try await follow(try await client.control.uninstall(appID: appID, deleteData: deleteData), verb: "removing")
    }
}

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Update one app, or all when no id is given.")
    @Argument var appID = ""

    func run() async throws {
        let client = try await connect()
        _ = try await client.command(.startVm(.init()))
        try await follow(try await client.control.update(appID: appID), verb: "updating")
    }
}

struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch an app in the guest. Its windows need the app's stub running; use `open` on the stub."
    )
    @Argument var appID: String

    func run() async throws {
        print(describe(try await connect().command(.launchApp(.with { $0.appID = appID })).state))
    }
}

struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stream guest and app log lines, or print the recent ones with --since.")
    @Option(help: "Print the lines of this recent span and exit, e.g. 30s, 5m, 2h. The agent keeps the newest 5,000.")
    var since: String?

    func run() async throws {
        let client = try await connect()
        if let since {
            let window = try Self.duration(since)
            let cutoff = Date().addingTimeInterval(-window).timeIntervalSince1970 * 1000
            for line in try await client.command(.getLogs(.with { $0.sinceMs = Int64(cutoff) })).logs {
                print("[\(line.source)] \(line.text)")
            }
            return
        }
        for await event in client.control.events {
            switch event {
            case .log(let line): print("[\(line.source)] \(line.text)")
            case .appStarted(let started): print("started \(started.appID) pid \(started.pid) launch \(started.launchID)")
            case .appExited(let exited): print("exited \(exited.appID) code \(exited.exitCode)")
            }
        }
    }

    /// `30s`, `5m`, `2h` (a bare number means seconds).
    static func duration(_ text: String) throws -> TimeInterval {
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600]
        let unit = text.last.flatMap { units[$0] }
        let number = unit == nil ? text : String(text.dropLast())
        guard let value = Double(number), value >= 0 else { throw ValidationError("invalid duration \(text)") }
        return value * (unit ?? 1)
    }
}

struct CatalogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "catalog", abstract: "Refresh and search the Flathub catalog.",
        subcommands: [Refresh.self, Search.self])

    struct Refresh: AsyncParsableCommand {
        func run() async throws {
            let client = try await connect()
            _ = try await client.command(.startVm(.init()))
            try await client.control.refreshCatalog()
            print("catalog refreshed")
        }
    }

    struct Search: AsyncParsableCommand {
        @Argument var query: String

        func run() async throws {
            let client = try await connect()
            _ = try await client.command(.startVm(.init()))
            let apps = try AppStreamParser.parse(gzipped: try await client.control.catalog())
            for app in CatalogIndex(apps: apps).search(query).prefix(10) {
                print("\(app.id)\t\(app.name)\t\(app.summary)")
            }
        }
    }
}

struct StubCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stub", abstract: "Create or remove an app's Dock/Launchpad stub.",
        subcommands: [Add.self, Remove.self])

    struct Add: AsyncParsableCommand {
        @Argument var appID: String
        @Argument var name: String
        @Option(help: "Path to CrosswindAppStub.app (default: the one inside Crosswind.app).") var template: String?

        func run() throws {
            let url = try template.map { URL(fileURLWithPath: $0) } ?? Self.bundledTemplate()
            let bundle = try StubInstaller(template: url).install(appID: appID, name: name, version: "1")
            print(bundle.path)
        }

        static func bundledTemplate() throws -> URL {
            guard let executable = Bundle.main.executableURL else { throw ValidationError("no executable path") }
            let url = executable.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Resources/CrosswindAppStub.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("pass --template; crosswindctl is not inside Crosswind.app")
            }
            return url
        }
    }

    struct Remove: AsyncParsableCommand {
        @Argument var appID: String

        func run() throws {
            try StubInstaller(template: URL(fileURLWithPath: "/"), directory: StubInstaller.defaultDirectory)
                .remove(appID: appID)
        }
    }
}

struct ImageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "image", abstract: "Install the guest image.", subcommands: [Install.self])

    struct Install: AsyncParsableCommand {
        @Argument(help: "Path to a GuestImage.json manifest (see scripts/image-manifest.sh).") var manifest: String

        func run() async throws {
            let data = try Data(contentsOf: URL(fileURLWithPath: manifest))
            let manifest = try JSONDecoder().decode(GuestImageManifest.self, from: data)
            let store = ImageStore(paths: .standard)
            try await store.install(manifest) { print(String(format: "\r%3.0f%%", $0 * 100), terminator: "") }
            print("\rinstalled image \(manifest.version)")
        }
    }
}

struct Windows: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List guest windows with frame and latency counters.")

    func run() async throws {
        let result = try await connect().command(.listWindows(.init()))
        for window in result.windows {
            let latency = String(format: "%.1f ms", window.lastInputToFrameMs)
            print("\(window.id)\t\(window.appID)\t\(window.width)x\(window.height)\t\(window.frames) frames\t\(latency)\t\(window.title)")
        }
    }
}

struct TypeText: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type", abstract: "Type text into a window (letters, digits, space) and report input-to-frame latency.")
    @Argument var window: UInt32
    @Argument var text: String

    /// evdev key codes for the characters supported here.
    private static let codes: [Character: UInt32] = {
        var map: [Character: UInt32] = [" ": 57]
        for (index, character) in "1234567890".enumerated() { map[character] = UInt32(2 + index) }
        for (index, character) in "qwertyuiop".enumerated() { map[character] = UInt32(16 + index) }
        for (index, character) in "asdfghjkl".enumerated() { map[character] = UInt32(30 + index) }
        for (index, character) in "zxcvbnm".enumerated() { map[character] = UInt32(44 + index) }
        return map
    }()

    func run() async throws {
        let client = try await connect()
        for character in text.lowercased() {
            guard let code = Self.codes[character] else { continue }
            for pressed in [true, false] {
                let key = Crosswind_Display_Input.OneOf_Event.key(.with { $0.keycode = code; $0.pressed = pressed })
                _ = try await client.command(.injectInput(.with { $0.input = .with { $0.window = window; $0.event = key } }))
            }
            try await Task.sleep(for: .milliseconds(300))
            let info = try await client.command(.listWindows(.init())).windows.first { $0.id == window }
            print("\(character): \(String(format: "%.1f", info?.lastInputToFrameMs ?? -1)) ms")
        }
    }
}

struct Click: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Click at a point (window-local points) and report latency.")
    @Argument var window: UInt32
    @Argument var x: Double
    @Argument var y: Double

    func run() async throws {
        let client = try await connect()
        func send(_ event: Crosswind_Display_Input.OneOf_Event) async throws {
            _ = try await client.command(.injectInput(.with { $0.input = .with { $0.window = window; $0.event = event } }))
        }
        try await send(.motion(.with { $0.x = x; $0.y = y }))
        try await Task.sleep(for: .milliseconds(100))
        for pressed in [true, false] {
            try await send(.button(.with { $0.button = 0x110; $0.pressed = pressed }))
            try await Task.sleep(for: .milliseconds(80))
        }
        try await Task.sleep(for: .milliseconds(500))
        let info = try await client.command(.listWindows(.init())).windows.first { $0.id == window }
        print(String(format: "click-to-frame %.1f ms", info?.lastInputToFrameMs ?? -1))
    }
}

struct Diagnose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a diagnostic bundle (zip): system, agent state, windows, apps, logs, with personal data redacted.")
    @Option(help: "Output .zip path (default: crosswind-diagnostics-<time>.zip in the current directory).")
    var output: String?

    func run() async throws {
        let client = try await connect()
        let snapshot = await DiagnosticBundle.collect(agent: client)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let destination = URL(fileURLWithPath: output ?? "crosswind-diagnostics-\(stamp).zip")
        print(try DiagnosticBundle.write(snapshot, to: destination).path)
        for problem in snapshot.problems { FileHandle.standardError.write(Data("warning: \(problem)\n".utf8)) }
    }
}

struct CompatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compat", abstract: "Test Flathub apps and record their compatibility.", subcommands: [Run.self])

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install, launch and check apps; writes results.json, matrix.md and screenshots.")
        @Option(help: "Comma-separated Flatpak app ids.") var ids: String?
        @Option(help: "A named set of apps: curated.") var set: String?
        @Option(help: "Seconds to wait for a window, a first frame, and an exit.") var timeout = 90
        @Flag(help: "Keep the apps installed afterwards.") var keep = false
        @Option(help: "Directory for results.json, matrix.md and screenshots/.") var dir = "docs/compat"
        @Option(help: "Also write the bundled ratings file to this path.") var ratings: String?

        func run() async throws {
            let appIDs: [String]
            if let ids {
                appIDs = ids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if set == "curated" {
                appIDs = CompatHarness.curatedSet
            } else if let set {
                throw HarnessError.unknownSet(set)
            } else {
                throw ValidationError("pass --ids or --set curated")
            }
            let client = try await connect()
            _ = try await client.command(.startVm(.init()))

            let directory = URL(fileURLWithPath: dir, isDirectory: true)
            let screenshots = directory.appending(path: "screenshots", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
            var options = CompatHarness.Options(screenshotDirectory: screenshots)
            options.timeout = .seconds(timeout)
            options.keepInstalled = keep
            options.imageVersion = ImageStore(paths: .standard).installedVersion() ?? "dev"

            let records = try await CompatHarness.run(ids: appIDs, control: client, options: options) {
                FileHandle.standardError.write(Data(($0 + "\n").utf8))
            }
            try CompatReport.write(
                records, directory: directory, ratingsFile: ratings.map { URL(fileURLWithPath: $0) })
            print(records.map { "\($0.status.rawValue)\t\($0.appID)" }.joined(separator: "\n"))
        }
    }
}
