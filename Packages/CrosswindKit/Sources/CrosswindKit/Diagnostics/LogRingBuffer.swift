// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One line in the diagnostics log: a guest line, an app start or exit, or a host log entry.
public struct LogEntry: Sendable, Identifiable, Equatable {
    public let id: UInt64
    public let time: Date
    public let source: String
    /// Syslog severity: 3 error, 4 warning, 6 info, 7 debug.
    public let level: Int32
    public let launchID: String
    public let text: String

    public var levelName: String {
        switch level {
        case ...3: "error"
        case 4: "warning"
        case 5, 6: "info"
        default: "debug"
        }
    }
}

/// Keeps the newest `capacity` entries. Trimming is amortized so appends stay cheap during log bursts.
public struct LogRingBuffer: Sendable {
    public static let defaultCapacity = 5_000

    public let capacity: Int
    private var storage: [LogEntry] = []
    private var nextID: UInt64 = 0

    public init(capacity: Int = LogRingBuffer.defaultCapacity) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
    }

    public var entries: ArraySlice<LogEntry> { storage.suffix(capacity) }

    public mutating func append(source: String, level: Int32, launchID: String = "", text: String, time: Date = Date()) {
        nextID += 1
        storage.append(LogEntry(id: nextID, time: time, source: source, level: level, launchID: launchID, text: text))
        if storage.count > capacity * 2 {
            storage.removeFirst(storage.count - capacity)
        }
    }
}
