// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit

/// The menu bar item of the background agent: the Linux environment's state, the running apps, and ways to open
/// the store or quit the agent.
@MainActor
final class StatusItemController: NSObject {
    private static let storeBundleID = "dev.crosswind.app"

    private let session: GuestSession
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let runningItem = NSMenuItem(title: String(localized: "Running Apps"), action: nil, keyEquivalent: "")
    private let runningMenu = NSMenu(title: String(localized: "Running Apps"))

    init(session: GuestSession) {
        self.session = session
        super.init()

        item.button?.image = NSImage(
            systemSymbolName: "shippingbox", accessibilityDescription: String(localized: "Crosswind Host"))
        item.button?.setAccessibilityLabel(String(localized: "Crosswind Host"))
        item.menu = buildMenu()
        render(session.state)

        Task { [weak self, session] in
            for await state in session.states { self?.render(state) }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Crosswind Host"))
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        runningItem.submenu = runningMenu
        menu.addItem(runningItem)

        let open = NSMenuItem(
            title: String(localized: "Open Crosswind"), action: #selector(openStore), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit Crosswind Host"), action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func render(_ state: Crosswind_Agent_State) {
        stateItem.title = String(localized: "Linux environment: \(Self.phaseName(state))")

        runningMenu.removeAllItems()
        if state.runningApps.isEmpty {
            let none = NSMenuItem(title: String(localized: "No Apps Running"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            runningMenu.addItem(none)
        }
        for appID in state.runningApps {
            let running = NSMenuItem(title: appID, action: nil, keyEquivalent: "")
            running.isEnabled = false
            runningMenu.addItem(running)
        }
    }

    private static func phaseName(_ state: Crosswind_Agent_State) -> String {
        let detail = state.detail
        switch state.phase {
        case .stopped: return String(localized: "Stopped")
        case .starting: return detail.isEmpty ? String(localized: "Starting…") : detail
        case .running: return String(localized: "Running")
        case .stopping: return String(localized: "Stopping…")
        case .failed: return detail.isEmpty ? String(localized: "Failed") : String(localized: "Failed: \(detail)")
        default: return String(localized: "Unknown")
        }
    }

    @objc private func openStore() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.storeBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        Task { _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) }
    }

    /// Terminating the agent stops the VM first (see `HostDelegate.applicationShouldTerminate`).
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
