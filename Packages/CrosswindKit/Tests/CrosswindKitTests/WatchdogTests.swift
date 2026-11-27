// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Synchronization
import Testing

@testable import CrosswindKit

@Suite struct WatchdogPolicyTests {
    @Test func aReplyIsHealthy() {
        var policy = WatchdogPolicy()
        #expect(policy.record(replied: true) == .healthy)
    }

    @Test func missesAreSuspectUntilTheToleranceThenHung() {
        var policy = WatchdogPolicy(tolerance: 3)
        #expect(policy.record(replied: false) == .suspect(count: 1))
        #expect(policy.record(replied: false) == .suspect(count: 2))
        #expect(policy.record(replied: false) == .hung)
    }

    @Test func aReplyClearsEarlierMisses() {
        var policy = WatchdogPolicy(tolerance: 3)
        _ = policy.record(replied: false)
        _ = policy.record(replied: false)
        #expect(policy.record(replied: true) == .healthy)
        #expect(policy.record(replied: false) == .suspect(count: 1))
    }

    @Test func aToleranceOfOneDeclaresTheFirstMissAHang() {
        var policy = WatchdogPolicy(tolerance: 1)
        #expect(policy.record(replied: false) == .hung)
    }
}

/// A thread-safe tally the watchdog's `@Sendable` closures can bump.
private final class Counter: Sendable {
    private let storage = Mutex(0)

    var value: Int { storage.withLock { $0 } }

    func increment() {
        storage.withLock { $0 += 1 }
    }
}

@MainActor
@Suite struct GuestWatchdogTests {
    private static let tick: Duration = .milliseconds(10)

    private func watchdog(
        heartbeat: @escaping @Sendable () async -> Bool, onHung: @escaping @MainActor () -> Void
    ) -> GuestWatchdog {
        GuestWatchdog(
            interval: Self.tick, replyTimeout: .milliseconds(30), policy: WatchdogPolicy(tolerance: 2),
            heartbeat: heartbeat, onHung: onHung)
    }

    @Test func aGuestThatKeepsAnsweringIsNeverReportedHung() async throws {
        let beats = Counter()
        var hung = false
        let dog = watchdog(
            heartbeat: {
                beats.increment()
                return true
            }, onHung: { hung = true })
        dog.start()
        try await Task.sleep(for: .milliseconds(150))
        dog.stop()
        #expect(beats.value >= 3)
        #expect(!hung)
    }

    @Test func aGuestThatRepliesFalseIsReportedHungOnce() async throws {
        let reports = Counter()
        let dog = watchdog(heartbeat: { false }, onHung: { reports.increment() })
        dog.start()
        try await Task.sleep(for: .milliseconds(250))
        #expect(reports.value == 1)
    }

    @Test func aHeartbeatThatNeverReturnsTimesOutAndIsReportedHung() async throws {
        let reports = Counter()
        let dog = watchdog(
            heartbeat: {
                await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in }
            },
            onHung: { reports.increment() })
        dog.start()
        try await Task.sleep(for: .milliseconds(400))
        #expect(reports.value == 1)
    }

    @Test func aStoppedWatchdogReportsNothing() async throws {
        let reports = Counter()
        let dog = watchdog(heartbeat: { false }, onHung: { reports.increment() })
        dog.start()
        dog.stop()
        try await Task.sleep(for: .milliseconds(150))
        #expect(reports.value == 0)
    }
}
