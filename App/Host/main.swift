// SPDX-License-Identifier: AGPL-3.0-or-later
// CrosswindHost: the background agent. launchd starts it on demand through its Mach service; it owns the Linux VM
// and routes windows to per-app stubs and guest control to the store app and crosswindctl.
import AppKit
import CrosswindKit

@MainActor
final class HostDelegate: NSObject, NSApplicationDelegate {
    private let session = GuestSession(paths: .standard)
    private var core: AgentCore?
    private var endpoint: AgentEndpoint?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let core = AgentCore(
            session: session, output: Self.mainScreenOutput, openURL: { NSWorkspace.shared.open($0) })
        self.core = core
        statusItem = StatusItemController(session: session)
        let endpoint = AgentEndpoint { connection, role, appID in
            Task { @MainActor in core.accept(connection, role: role, appID: appID) }
        }
        endpoint.resume()
        self.endpoint = endpoint
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await session.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func mainScreenOutput() -> Crosswind_Display_Output {
        let screen = NSScreen.main
        let size = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return .with {
            $0.width = UInt32(size.width)
            $0.height = UInt32(size.height)
            $0.scale120 = UInt32(((screen?.backingScaleFactor ?? 2) * 120).rounded())
            $0.refreshMhz = UInt32((screen?.maximumFramesPerSecond ?? 60) * 1000)
        }
    }
}

let application = NSApplication.shared
let delegate = HostDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
