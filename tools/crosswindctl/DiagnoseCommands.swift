// SPDX-License-Identifier: AGPL-3.0-or-later
import ArgumentParser
import CrosswindKit
import Foundation

struct Diagnose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract:
            "Write a diagnostic bundle (zip): system, agent state, windows, apps, logs, with personal data redacted.")
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
            options.imageVersion = await ImageStore(paths: .standard).installedVersion() ?? "dev"

            let ratingsFile = ratings.map { URL(fileURLWithPath: $0) }
            // Each app is written as soon as it is tested, so an interrupted run keeps what it finished.
            let records = try await CompatHarness.run(
                ids: appIDs, control: client, options: options,
                log: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
                onRecord: { record in
                    try? CompatReport.write([record], directory: directory, ratingsFile: ratingsFile)
                })
            print(records.map { "\($0.status.rawValue)\t\($0.appID)" }.joined(separator: "\n"))
        }
    }
}
