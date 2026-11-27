// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import Testing

@testable import Crosswind

@Suite struct OnboardingFlowTests {
    private func step(
        welcomed: Bool = true, finished: Bool = false, needsApproval: Bool = false,
        phase: StoreModel.Phase = .connecting
    ) -> OnboardingStep? {
        OnboardingFlow.step(welcomed: welcomed, finished: finished, needsApproval: needsApproval, phase: phase)
    }

    @Test func aFirstRunStartsWithTheWelcomeAndAsksForNothingYet() {
        #expect(step(welcomed: false) == .welcome)
        #expect(step(welcomed: false, needsApproval: true, phase: .ready) == .welcome)
    }

    @Test func approvalComesBeforeSetupAndSetupBeforeReady() {
        #expect(step(needsApproval: true) == .allowService)
        #expect(step(phase: .connecting) == .settingUp)
        #expect(step(phase: .installingImage(0.4)) == .settingUp)
        #expect(step(phase: .loadingCatalog) == .settingUp)
        #expect(step(phase: .failed("x")) == .settingUp)
        #expect(step(phase: .ready) == .ready)
    }

    @Test func aFinishedOnboardingNeverReturns() {
        #expect(step(finished: true, needsApproval: true, phase: .failed("x")) == nil)
        #expect(step(welcomed: false, finished: true) == nil)
    }

    @Test func stepsAreOrdered() {
        #expect(OnboardingStep.allCases == [.welcome, .allowService, .settingUp, .ready])
    }
}
