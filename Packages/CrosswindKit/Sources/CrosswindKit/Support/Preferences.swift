// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// User settings shared by the store app and every app stub (a common defaults domain, not each bundle's own).
public enum Preferences {
    nonisolated(unsafe) public static let suite = UserDefaults(suiteName: "dev.crosswind.shared") ?? .standard

    public enum Key {
        /// Command acts as Control in Linux apps (Cmd+C copies). Default on.
        public static let commandActsAsControl = "commandActsAsControl"
        /// Shares the clipboard with Linux apps while a Crosswind app is frontmost. Default on.
        public static let clipboardSync = "clipboardSync"
        /// Lets Linux apps record from the Mac's microphone. Off by default. Applies when the environment starts.
        public static let microphoneEnabled = "microphoneEnabled"
        /// Virtual CPUs given to the Linux environment. Applies when it starts.
        public static let cpuCount = "cpuCount"
        /// Memory in GiB given to the Linux environment. Applies when it starts.
        public static let memoryGiB = "memoryGiB"
        /// Minutes without apps, operations or windows before the environment stops. 0 keeps it running.
        public static let idleTimeoutMinutes = "idleTimeoutMinutes"
    }

    public static var commandActsAsControl: Bool {
        suite.object(forKey: Key.commandActsAsControl) as? Bool ?? true
    }

    public static var clipboardSync: Bool {
        suite.object(forKey: Key.clipboardSync) as? Bool ?? true
    }

    public static var microphoneEnabled: Bool {
        suite.object(forKey: Key.microphoneEnabled) as? Bool ?? false
    }

    // MARK: Resources

    private static let hostCores = ProcessInfo.processInfo.activeProcessorCount
    private static let hostGiB = Int(ProcessInfo.processInfo.physicalMemory >> 30)

    /// Half the host cores, between 2 and 8.
    public static var defaultCPUCount: Int { min(8, max(2, hostCores / 2)) }
    public static var cpuRange: ClosedRange<Int> { 2...8 }

    /// 4 GiB, between 2 GiB and half the host's memory.
    public static var defaultMemoryGiB: Int { min(memoryRange.upperBound, 4) }
    public static var memoryRange: ClosedRange<Int> { 2...max(2, hostGiB / 2) }

    public static let defaultIdleTimeoutMinutes = 10
    public static let idleTimeoutRange = 0...120

    public static var cpuCount: Int {
        clamp(suite.object(forKey: Key.cpuCount) as? Int ?? defaultCPUCount, to: cpuRange)
    }

    public static var memoryGiB: Int {
        clamp(suite.object(forKey: Key.memoryGiB) as? Int ?? defaultMemoryGiB, to: memoryRange)
    }

    /// nil when the environment never idles out.
    public static var idleTimeout: Duration? {
        let minutes = clamp(
            suite.object(forKey: Key.idleTimeoutMinutes) as? Int ?? defaultIdleTimeoutMinutes, to: idleTimeoutRange)
        return minutes == 0 ? nil : .seconds(minutes * 60)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
