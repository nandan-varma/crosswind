// SPDX-License-Identifier: AGPL-3.0-or-later
// Spike 2: boot the guest and show its windows. Usage: dev <image-dir> <data-disk>
import AppKit
import CrosswindKit

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var vm: GuestVM?
    var server: DisplayServer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let vm = GuestVM(imageDirectory: URL(fileURLWithPath: args[1]), dataDisk: URL(fileURLWithPath: args[2]))
        vm.onDisplayConnection = { [weak self] connection in self?.server = DisplayServer(connection: connection) }
        self.vm = vm
        Task { do { try await vm.start() } catch { print("vm start failed:", error); NSApp.terminate(nil) } }
    }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
