// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import OSLog
import ServiceManagement

/// Registers the background host agent (launchd, Mach service dev.crosswind.host) with the system and waits for the
/// user's approval in Login Items, which macOS requires the first time.
@MainActor
@Observable
final class HostRegistration {
    private static let logger = Logger(subsystem: "dev.crosswind", category: "registration")

    private(set) var needsApproval = false
    private var openedSettings = false

    /// Returns once the agent is enabled (or registration failed for a reason the user cannot fix by approving).
    func ensureEnabled() async {
        let agent = SMAppService.agent(plistName: "dev.crosswind.host.plist")
        while true {
            if agent.status == .notRegistered || agent.status == .notFound {
                do {
                    try agent.register()
                } catch {
                    Self.logger.error("Host agent registration failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            switch agent.status {
            case .enabled:
                needsApproval = false
                return
            case .requiresApproval:
                needsApproval = true
                if !openedSettings {
                    openedSettings = true
                    SMAppService.openSystemSettingsLoginItems()
                }
            default:
                needsApproval = false
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
