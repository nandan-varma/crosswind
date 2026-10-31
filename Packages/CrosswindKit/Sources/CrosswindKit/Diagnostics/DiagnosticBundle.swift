// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public struct SystemRecord: Codable, Sendable, Equatable {
    public var appVersion: String
    public var macOSVersion: String
    public var model: String
    public var memoryBytes: UInt64
    public var generatedAt: Date
}

public struct AgentStateRecord: Codable, Sendable, Equatable {
    public var phase: String
    public var detail: String
    public var runningApps: [String]
}

public struct WindowRecord: Codable, Sendable, Equatable {
    public var id: UInt32
    public var appID: String
    public var title: String
    public var width: UInt32
    public var height: UInt32
    public var scale120: UInt32
    public var frames: UInt64
    public var lastInputToFrameMs: Double
}

public struct InstalledRecord: Codable, Sendable, Equatable {
    public var appID: String
    public var name: String
    public var version: String
    public var branch: String
    public var installedSize: UInt64
    public var updateAvailable: Bool
}

public struct ReportExcerpt: Sendable, Equatable {
    public var name: String
    public var lines: [String]
}

/// Everything a diagnostic bundle contains, gathered before any redaction or file writing.
public struct DiagnosticSnapshot: Sendable {
    public var system: SystemRecord
    /// nil when the agent could not be asked; the reason goes to `problems`.
    public var agentState: AgentStateRecord?
    public var windows: [WindowRecord]?
    public var installed: [InstalledRecord]?
    public var guestLogs: [LogEntry]
    public var hostLogs: [String]
    public var reports: [ReportExcerpt]
    public var supportDirectoryBytes: UInt64?
    public var problems: [String]
}

/// Builds the diagnostics bundle: a folder of JSON and text files, every line passed through `Redactor`, zipped with ditto.
public enum DiagnosticBundle {
    public static let guestLogLimit = 5_000
    public static let hostLogLimit = 500
    public static let reportLineLimit = 200

    public enum WriteError: Error, Equatable {
        case zipFailed(Int32)
    }

    /// Gathers the snapshot from the agent, the host log store, DiagnosticReports and the support directory.
    public static func collect(
        agent: AgentClient, guestLogs: [LogEntry], paths: GuestPaths = .standard, now: Date = Date()
    ) async -> DiagnosticSnapshot {
        var problems: [String] = []
        var state: AgentStateRecord?
        do {
            let result = try await agent.command(.getState(.init()))
            state = AgentStateRecord(
                phase: "\(result.state.phase)", detail: result.state.detail, runningApps: result.state.runningApps)
        } catch {
            problems.append("agent state: \(error)")
        }
        var windows: [WindowRecord]?
        do {
            windows = try await agent.command(.listWindows(.init())).windows.map(WindowRecord.init)
        } catch {
            problems.append("windows: \(error)")
        }
        var installed: [InstalledRecord]?
        do {
            installed = try await agent.control.installed().map(InstalledRecord.init)
        } catch {
            problems.append("installed apps: \(error)")
        }
        let host = await Task.detached { HostLogReader.recent(limit: hostLogLimit) }.value
        if let note = host.note { problems.append("host logs: \(note)") }
        return DiagnosticSnapshot(
            system: systemRecord(now: now),
            agentState: state,
            windows: windows,
            installed: installed,
            guestLogs: Array(guestLogs.suffix(guestLogLimit)),
            hostLogs: host.lines,
            reports: await Task.detached { crosswindReports() }.value,
            supportDirectoryBytes: directorySize(paths.supportDirectory),
            problems: problems)
    }

    /// The bundle's files as relative path and content, with redaction applied. Pure, so it can be tested.
    public static func files(for snapshot: DiagnosticSnapshot, redactor: Redactor = Redactor()) throws -> [(String, Data)] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        func json<T: Encodable>(_ value: T) throws -> Data {
            let data = try encoder.encode(value)
            guard let text = String(data: data, encoding: .utf8) else { return data }
            return Data(redactor.redact(text).utf8)
        }
        func text(_ lines: [String]) -> Data {
            Data(redactor.redact(lines.joined(separator: "\n") + "\n").utf8)
        }

        var files: [(String, Data)] = [("system.json", try json(snapshot.system))]
        if let state = snapshot.agentState { files.append(("agent-state.json", try json(state))) }
        if let windows = snapshot.windows { files.append(("windows.json", try json(windows))) }
        if let installed = snapshot.installed { files.append(("installed-apps.json", try json(installed))) }
        let guestLines = snapshot.guestLogs.map { entry in
            "\(entry.time.formatted(.iso8601)) [\(entry.source)] \(entry.levelName) \(entry.launchID) \(entry.text)"
        }
        files.append(("guest-logs.txt", text(guestLines)))
        files.append(("host-logs.txt", text(snapshot.hostLogs)))
        for report in snapshot.reports {
            files.append(("diagnostic-reports/\(report.name).txt", text(report.lines)))
        }
        if let bytes = snapshot.supportDirectoryBytes {
            files.append(("disk-usage.json", try json(["supportDirectoryBytes": bytes])))
        }
        if !snapshot.problems.isEmpty { files.append(("problems.txt", text(snapshot.problems))) }
        return files
    }

    /// Writes the bundle to `destination` as a zip archive and returns that URL.
    public static func write(
        _ snapshot: DiagnosticSnapshot, to destination: URL, redactor: Redactor = Redactor()
    ) throws -> URL {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appending(
            path: "crosswind-diag-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        let folder = staging.appending(path: "crosswind-diagnostics", directoryHint: .isDirectory)
        for (path, data) in try files(for: snapshot, redactor: redactor) {
            let url = folder.appending(path: path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try? fileManager.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", folder.path, destination.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw WriteError.zipFailed(ditto.terminationStatus) }
        return destination
    }

    static func systemRecord(now: Date) -> SystemRecord {
        SystemRecord(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: sysctlString("hw.model") ?? "unknown",
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            generatedAt: now)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Crash and hang reports whose names mention Crosswind; first `reportLineLimit` lines of each.
    static func crosswindReports() -> [ReportExcerpt] {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.localizedCaseInsensitiveContains("crosswind") }.sorted().compactMap { name in
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                let text = String(data: data, encoding: .utf8)
            else { return nil }
            let lines = text.split(separator: "\n", maxSplits: reportLineLimit, omittingEmptySubsequences: false)
            return ReportExcerpt(name: name, lines: lines.prefix(reportLineLimit).map(String.init))
        }
    }

    static func directorySize(_ url: URL) -> UInt64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        else { return nil }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            total += UInt64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

extension WindowRecord {
    init(_ info: Crosswind_Agent_WindowInfo) {
        self.init(
            id: info.id, appID: info.appID, title: info.title, width: info.width, height: info.height,
            scale120: info.scale120, frames: info.frames, lastInputToFrameMs: info.lastInputToFrameMs)
    }
}

extension InstalledRecord {
    init(_ app: Crosswind_Control_InstalledApp) {
        self.init(
            appID: app.appID, name: app.name, version: app.version, branch: app.branch,
            installedSize: app.installedSize, updateAvailable: app.updateAvailable)
    }
}
