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
        print(describe(try await connect().command(.startVm(.init()))))
    }
}

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Shut the Linux environment down.")

    func run() async throws {
        print(describe(try await connect().command(.stopVm(.init()))))
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
        print(describe(try await connect().command(.launchApp(.with { $0.appID = appID }))))
    }
}

struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stream guest and app log lines.")

    func run() async throws {
        let client = try await connect()
        for await event in client.control.events {
            switch event {
            case .log(let line): print("[\(line.source)] \(line.text)")
            case .appStarted(let started): print("started \(started.appID) pid \(started.pid) launch \(started.launchID)")
            case .appExited(let exited): print("exited \(exited.appID) code \(exited.exitCode)")
            }
        }
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
