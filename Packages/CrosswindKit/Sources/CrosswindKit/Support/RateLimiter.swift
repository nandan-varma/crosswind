// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Token bucket: `burst` events at once, refilled at `perSecond`. Thread-safe, so one instance can guard a log
/// line or a guest's call stream from any thread. Time is injectable for tests.
public final class RateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Double
    private let refillPerSecond: Double
    private var tokens: Double
    private var last: ContinuousClock.Instant?

    public init(perSecond: Double, burst: Int) {
        capacity = Double(burst)
        refillPerSecond = perSecond
        tokens = Double(burst)
    }

    /// Convenience for "n per minute".
    public convenience init(perMinute: Int) {
        self.init(perSecond: Double(perMinute) / 60, burst: perMinute)
    }

    /// Takes one token if available.
    public func allow(now: ContinuousClock.Instant = .now) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last {
            let elapsed = now - last
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            tokens = min(capacity, tokens + max(0, seconds) * refillPerSecond)
        }
        last = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}
