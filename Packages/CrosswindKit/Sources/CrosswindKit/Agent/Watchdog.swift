// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Synchronization

/// Decides from a run of heartbeat results whether the guest is hung. Pure, so the thresholds are testable.
///
/// A control channel that is open proves little: the guest daemon can deadlock, or the kernel can wedge, with the
/// vsock connection still up. A hang is declared only after `tolerance` consecutive missed heartbeats, so one slow
/// reply (a busy guest installing an app) does not restart the environment.
public struct WatchdogPolicy: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        case healthy
        /// The guest missed `count` heartbeats in a row but is not yet declared hung.
        case suspect(count: Int)
        case hung
    }

    /// Consecutive missed heartbeats that make a hang.
    public let tolerance: Int
    public private(set) var missed = 0

    public init(tolerance: Int = 3) {
        precondition(tolerance > 0, "a watchdog needs at least one miss to act on")
        self.tolerance = tolerance
    }

    /// Records one heartbeat result. A reply clears the count.
    public mutating func record(replied: Bool) -> Verdict {
        guard !replied else {
            missed = 0
            return .healthy
        }
        missed += 1
        return missed >= tolerance ? .hung : .suspect(count: missed)
    }
}

/// Sends the guest a heartbeat at a fixed interval and reports when it stops answering.
@MainActor
public final class GuestWatchdog {
    /// Time between heartbeats.
    public static let interval: Duration = .seconds(10)
    /// How long one heartbeat may take before it counts as missed.
    public static let replyTimeout: Duration = .seconds(5)

    private let interval: Duration
    private let replyTimeout: Duration
    private let heartbeat: @Sendable () async -> Bool
    private let onHung: @MainActor () -> Void
    private var policy: WatchdogPolicy
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - heartbeat: sends one request to the guest; true when the guest replied.
    ///   - onHung: called once, when the guest has missed the policy's tolerance. The watchdog then stops itself.
    public init(
        interval: Duration = GuestWatchdog.interval,
        replyTimeout: Duration = GuestWatchdog.replyTimeout,
        policy: WatchdogPolicy = WatchdogPolicy(),
        heartbeat: @escaping @Sendable () async -> Bool,
        onHung: @escaping @MainActor () -> Void
    ) {
        self.interval = interval
        self.replyTimeout = replyTimeout
        self.policy = policy
        self.heartbeat = heartbeat
        self.onHung = onHung
    }

    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if await self.beat() == .hung {
                    self.task = nil
                    self.onHung()
                    return
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func beat() async -> WatchdogPolicy.Verdict {
        let replied = await Self.race(heartbeat, timeout: replyTimeout)
        guard !Task.isCancelled else { return .healthy }
        let verdict = policy.record(replied: replied)
        if case .suspect(let count) = verdict {
            Log.vm.warning("guest missed heartbeat \(count) of \(self.policy.tolerance)")
        }
        return verdict
    }

    /// True when `work` finished true before `timeout`; false when it returned false or ran out of time.
    ///
    /// Not a task group: a group waits for every child, and a heartbeat stuck on a guest that never replies cannot be
    /// cancelled. The first result wins and a stuck heartbeat is abandoned (the session tears the guest down).
    private static func race(_ work: @escaping @Sendable () async -> Bool, timeout: Duration) async -> Bool {
        let outcome = Mutex<CheckedContinuation<Bool, Never>?>(nil)
        return await withCheckedContinuation { continuation in
            outcome.withLock { $0 = continuation }
            let finish: @Sendable (Bool) -> Void = { value in
                outcome.withLock { pending in
                    pending?.resume(returning: value)
                    pending = nil
                }
            }
            let heartbeat = Task { finish(await work()) }
            Task {
                try? await Task.sleep(for: timeout)
                finish(false)
                heartbeat.cancel()
            }
        }
    }
}

extension AgentCore {
    /// The watchdog's heartbeat: the cheapest request the guest answers (listing running apps). True on any reply.
    func pingGuest() async -> Bool {
        (try? await request(.listRunning(Crosswind_Control_ListRunning()))) != nil
    }
}
