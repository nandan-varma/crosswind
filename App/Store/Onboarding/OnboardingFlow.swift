// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import Observation

/// The screens a first run goes through, in order.
enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case allowService
    case settingUp
    case ready
}

/// Which onboarding screen to show, from what is known right now. Pure, so the order and the conditions are tested.
enum OnboardingFlow {
    /// Nil once onboarding is finished: the store shows. Before the welcome screen is passed, nothing else happens, so
    /// macOS is not asked to approve a background item before the user knows why.
    static func step(
        welcomed: Bool, finished: Bool, needsApproval: Bool, phase: StoreModel.Phase
    ) -> OnboardingStep? {
        if finished { return nil }
        if !welcomed { return .welcome }
        if needsApproval { return .allowService }
        if case .ready = phase { return .ready }
        return .settingUp
    }
}

/// The two persisted facts about onboarding, observable so the views and the app's startup task follow them.
@MainActor
@Observable
final class OnboardingState {
    private(set) var welcomed: Bool
    private(set) var finished: Bool

    init() {
        welcomed = Preferences.suite.bool(forKey: Preferences.Key.onboardingWelcomed)
        finished = Preferences.suite.bool(forKey: Preferences.Key.onboardingFinished)
    }

    func welcome() {
        welcomed = true
        Preferences.suite.set(true, forKey: Preferences.Key.onboardingWelcomed)
    }

    func finish() {
        finished = true
        Preferences.suite.set(true, forKey: Preferences.Key.onboardingFinished)
    }
}
