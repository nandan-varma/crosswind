// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import OSLog

/// Reads recent `dev.crosswind` unified-log entries. Falls back to the current process when the system store is closed.
public enum HostLogReader {
    public struct Result: Sendable {
        public let lines: [String]
        /// Why the scope is narrower than requested, or nil when the system store was read.
        public let note: String?
    }

    public static let subsystem = "dev.crosswind"

    public static func recent(limit: Int = 500, since: Date = Date().addingTimeInterval(-3600)) -> Result {
        do {
            return Result(lines: try read(from: try OSLogStore.local(), since: since, limit: limit), note: nil)
        } catch {
            let note = "system log store unavailable (\(error.localizedDescription)); current process only"
            let lines = (try? read(from: try OSLogStore(scope: .currentProcessIdentifier), since: since, limit: limit)) ?? []
            return Result(lines: lines, note: note)
        }
    }

    static func read(from store: OSLogStore, since: Date, limit: Int) throws -> [String] {
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let entries = try store.getEntries(at: store.position(date: since), matching: predicate)
        let lines = entries.compactMap { entry -> String? in
            guard let log = entry as? OSLogEntryLog else { return nil }
            return "\(log.date.formatted(.iso8601)) \(log.category) \(log.level.name): \(log.composedMessage)"
        }
        return Array(lines.suffix(limit))
    }
}

extension OSLogEntryLog.Level {
    var name: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "undefined"
        }
    }
}
