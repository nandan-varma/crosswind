// SPDX-License-Identifier: AGPL-3.0-or-later
import Darwin
import Foundation

/// Resident memory and cumulative CPU time of another process, read with `proc_pidinfo`.
public struct ProcessSample: Sendable, Equatable {
    public let residentBytes: UInt64
    public let cpuSeconds: Double
    public let wall: Date
}

public enum ProcessSampler {
    public static func sample(pid: pid_t, at now: Date = Date()) -> ProcessSample? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(info.pti_total_user) + Double(info.pti_total_system)
        let nanos = ticks * Double(timebase.numer) / Double(timebase.denom)
        return ProcessSample(residentBytes: info.pti_resident_size, cpuSeconds: nanos / 1e9, wall: now)
    }

    /// Average CPU use between two samples of the same process, in percent of one core.
    public static func cpuPercent(from earlier: ProcessSample, to later: ProcessSample) -> Double? {
        let elapsed = later.wall.timeIntervalSince(earlier.wall)
        guard elapsed > 0 else { return nil }
        return max(0, (later.cpuSeconds - earlier.cpuSeconds) / elapsed * 100)
    }
}
