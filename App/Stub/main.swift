// SPDX-License-Identifier: AGPL-3.0-or-later
// CrosswindAppStub: one generated copy per installed Linux app. It gives the app its own Dock tile, Cmd-Tab entry
// and Launchpad/Spotlight presence, and hosts the app's native windows. `CrosswindAppID` in Info.plist names the app.
import AppKit
import CrosswindKit

/// AppKit does not deliver `keyUp` to the first responder while Command is held; guest apps need the release.
final class StubApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyUp, event.modifierFlags.contains(.command), let responder = keyWindow?.firstResponder {
            responder.keyUp(with: event)
        } else {
            super.sendEvent(event)
        }
    }
}

@MainActor
final class StubDelegate: NSObject, NSApplicationDelegate {
    private let appID = Bundle.main.object(forInfoDictionaryKey: "CrosswindAppID") as? String ?? ""
    private var client: AgentClient?
    private var server: DisplayServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let client = try await AgentClient.connect(role: .stub, appID: appID)
                self.client = client
                server = DisplayServer(
                    messages: client.display, send: { message in Task { await client.send(display: message) } })
                watchForExit(client)
                _ = try await client.command(.launchApp(.with { $0.appID = appID }))
            } catch {
                present(error)
            }
        }
    }

    /// The app ending in the guest ends its stub.
    private func watchForExit(_ client: AgentClient) {
        Task { [appID] in
            for await event in client.control.events {
                if case .appExited(let exited) = event, exited.appID == appID { await NSApp.terminate(nil) }
            }
            await NSApp.terminate(nil)  // the agent went away
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't start \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") ?? appID)"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let application = StubApplication.shared
let delegate = StubDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
