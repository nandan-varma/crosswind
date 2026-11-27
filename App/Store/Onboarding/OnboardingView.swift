// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI

/// The first-run experience: welcome, allowing the background service, setting up, and picking a first app. One
/// continuous window; the screens slide past each other and a row of dots shows where the user is.
struct OnboardingView: View {
    let step: OnboardingStep
    let model: StoreModel
    let registration: HostRegistration
    let onboarding: OnboardingState
    /// Starts the connection again after a failure (re-registering the agent first).
    let retry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingBackground()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                screen
                    .id(step)
                    .transition(transition)
                    .frame(maxWidth: step == .ready ? 760 : 540)
                    .padding(.horizontal, 32)
                Spacer(minLength: 24)
                StepDots(current: step).padding(.bottom, 28)
            }
        }
        .animation(.smooth(duration: 0.5), value: step)
    }

    @ViewBuilder private var screen: some View {
        switch step {
        case .welcome:
            WelcomeStep(onContinue: onboarding.welcome)
        case .allowService:
            AllowServiceStep(registration: registration)
        case .settingUp:
            SettingUpStep(phase: model.phase, retry: retry)
        case .ready:
            ReadyStep(model: model, onFinish: onboarding.finish)
        }
    }

    /// Screens slide in from the right and out to the left; with Reduce Motion they only fade.
    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity))
    }
}

/// A soft mesh of the brand colors behind everything, tinted to suit light and dark appearances.
private struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.55 : 0.32
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .blue.opacity(strength), .cyan.opacity(strength * 0.6), .purple.opacity(strength * 0.8),
                .indigo.opacity(strength * 0.5), .blue.opacity(strength * 0.3), .indigo.opacity(strength * 0.6),
                .purple.opacity(strength * 0.6), .indigo.opacity(strength * 0.4), .blue.opacity(strength * 0.7),
            ]
        )
        .background(.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Where the user is in the flow: the current screen is a wider capsule.
private struct StepDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(
                        step == current
                            ? Color.accentColor : Color.primary.opacity(step.rawValue < current.rawValue ? 0.45 : 0.18)
                    )
                    .frame(width: step == current ? 26 : 8, height: 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("Setup progress"))
        .accessibilityValue(Text("Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count)"))
    }
}

/// The app's own icon, large, with a slow float that stops under Reduce Motion.
struct HeroIcon: View {
    var size: CGFloat = 132
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let icon = Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        if reduceMotion {
            icon
        } else {
            icon.phaseAnimator([0.0, -6.0]) { view, offset in
                view.offset(y: offset)
            } animation: { _ in
                .easeInOut(duration: 2.6)
            }
        }
    }
}
