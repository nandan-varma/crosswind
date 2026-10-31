// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The agent's copy of guest log lines: the newest `capacity` LogLine events, served by the `GetLogs` command.
public struct GuestLogStore: Sendable {
    public static let defaultCapacity = 5_000

    public let capacity: Int
    private var storage: [Crosswind_Control_LogLine] = []

    public init(capacity: Int = GuestLogStore.defaultCapacity) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
    }

    /// Longest text kept per line; longer lines from a guest app are cut.
    public static let maxTextBytes = 4096
    public static let maxFieldBytes = 256

    public mutating func append(_ line: Crosswind_Control_LogLine) {
        var line = line
        line.text = DisplayLimits.sanitize(line.text, maxBytes: Self.maxTextBytes)
        line.source = DisplayLimits.sanitize(line.source, maxBytes: Self.maxFieldBytes)
        line.launchID = DisplayLimits.sanitize(line.launchID, maxBytes: Self.maxFieldBytes)
        storage.append(line)
        if storage.count > capacity * 2 {
            storage.removeFirst(storage.count - capacity)
        }
    }

    /// Lines with `unixTimeMs >= sinceMs`, oldest first. A non-positive `sinceMs` returns everything kept.
    public func lines(sinceMs: Int64) -> [Crosswind_Control_LogLine] {
        storage.suffix(capacity).filter { $0.unixTimeMs >= sinceMs }
    }
}
