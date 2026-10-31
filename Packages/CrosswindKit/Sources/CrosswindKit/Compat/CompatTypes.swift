// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Outcome of one harness check. `unknown` means the check could not decide (for example, no frame after input).
public enum CheckOutcome: String, Codable, Sendable, Equatable {
    case pass, fail, unknown, skipped
}

/// What the harness observed for one app.
public struct CompatChecks: Codable, Sendable, Equatable {
    public var windowAppears: CheckOutcome = .skipped
    public var renders: CheckOutcome = .skipped
    public var inputWorks: CheckOutcome = .skipped
    public var noCrash: CheckOutcome = .skipped
    public var cleanExit: CheckOutcome = .skipped
    /// The app logged that it needs an X server (an X11 satellite or XWayland).
    public var needsX11 = false

    public init() {}
}

/// The rating shown to users. `noArmBuild` and `untested` are set by the harness, never by `CompatClassifier`.
public enum CompatStatus: String, Codable, Sendable, CaseIterable {
    case works
    case caveats
    case broken
    case noArmBuild = "no-arm-build"
    case untested

    /// Order in the matrix: best first.
    public var sortRank: Int {
        switch self {
        case .works: 0
        case .caveats: 1
        case .broken: 2
        case .noArmBuild: 3
        case .untested: 4
        }
    }

    public var title: String {
        switch self {
        case .works: "Works"
        case .caveats: "Works with caveats"
        case .broken: "Known issues"
        case .noArmBuild: "No ARM build"
        case .untested: "Not yet tested"
        }
    }
}

public enum CompatClassifier {
    public static func status(for checks: CompatChecks) -> CompatStatus {
        if checks.windowAppears != .pass || checks.noCrash == .fail || checks.renders != .pass {
            return .broken
        }
        if checks.inputWorks != .pass || checks.cleanExit != .pass || checks.needsX11 {
            return .caveats
        }
        return .works
    }
}

/// One app's result as stored in `docs/compat/results.json`.
public struct CompatRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { appID }
    public var appID: String
    public var name: String
    public var status: CompatStatus
    public var checks: CompatChecks
    public var notes: [String]
    public var testedAt: Date
    public var guestImageVersion: String
    public var appVersion: String
    public var arch: String
    /// Path of the screenshot relative to `docs/compat`, when one was taken.
    public var screenshot: String?

    public init(
        appID: String, name: String, status: CompatStatus, checks: CompatChecks = CompatChecks(),
        notes: [String] = [], testedAt: Date, guestImageVersion: String, appVersion: String = "", arch: String,
        screenshot: String? = nil
    ) {
        self.appID = appID
        self.name = name
        self.status = status
        self.checks = checks
        self.notes = notes
        self.testedAt = testedAt
        self.guestImageVersion = guestImageVersion
        self.appVersion = appVersion
        self.arch = arch
        self.screenshot = screenshot
    }
}

/// The on-disk shape of `docs/compat/results.json`.
public struct CompatResultsFile: Codable, Sendable, Equatable {
    public var apps: [CompatRecord]

    public init(apps: [CompatRecord]) {
        self.apps = apps
    }
}

public enum CompatResults {
    /// Newer records replace older ones with the same app id. The result is sorted by app id.
    public static func merge(_ new: [CompatRecord], into existing: [CompatRecord]) -> [CompatRecord] {
        var byID: [String: CompatRecord] = [:]
        for record in existing { byID[record.appID] = record }
        for record in new { byID[record.appID] = record }
        return byID.values.sorted { $0.appID < $1.appID }
    }

    public static func encode(_ records: [CompatRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(CompatResultsFile(apps: records))
    }

    public static func decode(_ data: Data) throws -> [CompatRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CompatResultsFile.self, from: data).apps
    }
}

public enum CompatError: Error, Equatable {
    case timeout
    case pngFailed(String)
}
