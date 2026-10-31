// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite struct VMLifecycleTests {
    @Test func anyRunningAppOperationWindowOrRequestMakesTheEnvironmentBusy() {
        #expect(!IdlePolicy.isBusy(apps: 0, operations: 0, windows: 0, requests: 0))
        #expect(IdlePolicy.isBusy(apps: 1, operations: 0, windows: 0, requests: 0))
        #expect(IdlePolicy.isBusy(apps: 0, operations: 1, windows: 0, requests: 0))
        #expect(IdlePolicy.isBusy(apps: 0, operations: 0, windows: 1, requests: 0))
        #expect(IdlePolicy.isBusy(apps: 0, operations: 0, windows: 0, requests: 1))
    }

    @Test func busyEnvironmentWaitsEvenAfterALongIdleSpell() {
        let action = IdlePolicy.action(busy: true, idleFor: .seconds(3600), timeout: .seconds(600))
        #expect(action == .wait)
    }

    @Test func justBecameIdleWaits() {
        #expect(IdlePolicy.action(busy: false, idleFor: .seconds(5), timeout: .seconds(600)) == .wait)
    }

    @Test func idleLongEnoughShrinksMemoryButKeepsRunning() {
        let action = IdlePolicy.action(busy: false, idleFor: IdlePolicy.shrinkAfter, timeout: .seconds(600))
        #expect(action == .shrink)
    }

    @Test func idleUntilTheTimeoutStops() {
        #expect(IdlePolicy.action(busy: false, idleFor: .seconds(599), timeout: .seconds(600)) == .shrink)
        #expect(IdlePolicy.action(busy: false, idleFor: .seconds(600), timeout: .seconds(600)) == .stop)
    }

    @Test func noTimeoutNeverStopsButStillShrinks() {
        #expect(IdlePolicy.action(busy: false, idleFor: .seconds(7200), timeout: nil) == .shrink)
    }

    @Test func timeoutShorterThanShrinkDelayStopsWithoutShrinking() {
        let action = IdlePolicy.action(busy: false, idleFor: .seconds(60), timeout: .seconds(60))
        #expect(action == .stop)
    }

    @Test func unknownIdleStartWaits() {
        #expect(IdlePolicy.action(busy: false, idleFor: nil, timeout: .seconds(600)) == .wait)
    }
}
