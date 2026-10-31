// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import OSLog
import ServiceManagement

/// Registers the background host agent (launchd, Mach service dev.crosswind.host) with the system.
@MainActor
enum HostRegistration {
    private static let logger = Logger(subsystem: "dev.crosswind", category: "registration")

    static func register() {
        let agent = SMAppService.agent(plistName: "dev.crosswind.host.plist")
        switch agent.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            do {
                try agent.register()
            } catch {
                logger.error("Host agent registration failed: \(error.localizedDescription, privacy: .public)")
            }
            if agent.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        @unknown default:
            logger.error("Host agent has an unknown status")
        }
    }
}
