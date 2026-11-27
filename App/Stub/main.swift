// SPDX-License-Identifier: AGPL-3.0-or-later
// CrosswindAppStub: one generated copy per installed Linux app. It gives the app its own Dock tile, Cmd-Tab entry
// and Launchpad/Spotlight presence, and hosts the app's native windows. `CrosswindAppID` in Info.plist names the app.
import AppKit
import CrosswindKit
import UserNotifications

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
    private let fileChooser = FileChooserHandler()
    /// Files and links macOS handed over before the app started; they go on its command line.
    private var pendingURLs: [URL] = []
    private var started = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        StubMenu.install(appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? appID)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let client = try await AgentClient.connect(role: .stub, appID: appID)
                self.client = client
                fileChooser.refreshShares = { _ = try? await client.command(.refreshShares(.init())) }
                server = DisplayServer(
                    messages: client.display, send: { message in Task { await client.send(display: message) } })
                watchForExit(client)
                answerCalls(client)
                let args = await fileChooser.arguments(forOpening: pendingURLs)
                pendingURLs = []
                started = true
                _ = try await client.command(
                    .launchApp(
                        .with {
                            $0.appID = appID
                            $0.args = args
                        }))
            } catch {
                present(error)
            }
        }
    }

    /// Files and links opened with this app: on its command line when it starts, else passed to the running app
    /// by a second launch (Flatpak forwards it to the first instance).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard started, let client else {
            pendingURLs += urls
            return
        }
        Task {
            let args = await fileChooser.arguments(forOpening: urls)
            _ = try? await client.command(
                .launchApp(
                    .with {
                        $0.appID = appID
                        $0.args = args
                    }))
        }
    }

    /// Clicking the Dock tile of a running app without windows (a GApplication that stays alive after its last
    /// window closed) asks the app to show a window again, as Linux launchers do.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, let client {
            Task { _ = try? await client.command(.launchApp(.with { $0.appID = appID })) }
        }
        return true
    }

    /// The app ending in the guest ends its stub.
    private func watchForExit(_ client: AgentClient) {
        Task { [appID] in
            var launches = LaunchTracker()
            for await event in client.control.events {
                switch event {
                case .appStarted(let started) where started.appID == appID:
                    launches.started(appID: appID, launchID: started.launchID)
                case .appExited(let exited) where exited.appID == appID:
                    // A launch that only forwarded files to the running app exits at once; that is not a quit.
                    if launches.exited(appID: appID, launchID: exited.launchID) { await NSApp.terminate(nil) }
                default:
                    break
                }
            }
            await NSApp.terminate(nil)  // the agent went away
        }
    }

    /// Requests the guest makes of the host for this app: notifications now, file dialogs later.
    private func answerCalls(_ client: AgentClient) {
        Task {
            for await call in client.control.calls {
                switch call.body {
                case .notify(let notify)?:
                    await post(notify)
                    await client.control.reply(to: call, .ok(.init()))
                case .fileChooser(let request)?:
                    // Each panel is its own task, so one open panel never delays notifications.
                    Task { await client.control.reply(to: call, await fileChooser.handle(request)) }
                default:
                    await client.control.reply(to: call, .error(.with { $0.message = "not supported yet" }))
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileChooser.finish()
    }

    private func post(_ notify: Crosswind_Control_Notify) async {
        let center = UNUserNotificationCenter.current()
        if notify.withdraw {
            center.removeDeliveredNotifications(withIdentifiers: [notify.notificationID])
            return
        }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = notify.title
        content.body = notify.body
        let request = UNNotificationRequest(identifier: notify.notificationID, content: content, trigger: nil)
        try? await center.add(request)
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? appID
        alert.messageText = String(localized: "Couldn't start \(name)")
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
