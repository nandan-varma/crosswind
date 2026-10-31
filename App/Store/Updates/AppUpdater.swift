// SPDX-License-Identifier: AGPL-3.0-or-later
import Observation
import Sparkle

/// Owns Sparkle's standard updater for the store app. Automatic checks are on by default (`SUEnableAutomaticChecks`
/// in Info.plist); system profiling is off (`SUEnableSystemProfiling`), so Sparkle sends only what it needs.
@MainActor
@Observable
final class AppUpdater {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
