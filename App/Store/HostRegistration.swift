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
    /// Why the agent could not be registered, when macOS refused; shown instead of a vague connection error.
    private(set) var failure: String?
    private var openedSettings = false

    /// Returns once the agent is enabled (or registration failed for a reason the user cannot fix by approving).
    func ensureEnabled() async {
        let agent = SMAppService.agent(plistName: "dev.crosswind.host.plist")
        while true {
            Self.logger.notice("host agent status: \(agent.status.rawValue, privacy: .public)")
            if agent.status == .notRegistered || agent.status == .notFound {
                do {
                    try agent.register()
                    failure = nil
                } catch {
                    failure = error.localizedDescription
                    Self.logger.error("Host agent registration failed: \(error.localizedDescription, privacy: .public)")
                }
                Self.logger.notice("host agent status after register: \(agent.status.rawValue, privacy: .public)")
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

    /// macOS can remember an approval for the agent while launchd has no job loaded, for instance after Crosswind is
    /// deleted and installed again. Registering afresh loads it; an approval macOS still holds is not asked again.
    func repair() async {
        let agent = SMAppService.agent(plistName: "dev.crosswind.host.plist")
        try? await agent.unregister()
        do {
            try agent.register()
            failure = nil
        } catch {
            failure = error.localizedDescription
            Self.logger.error("Host agent re-registration failed: \(error.localizedDescription, privacy: .public)")
        }
        await ensureEnabled()
    }
}
