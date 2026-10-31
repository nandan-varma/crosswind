// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI

@main
struct CrosswindApp: App {
    @State private var model = Self.makeModel()
    @State private var registration = HostRegistration()
    @State private var diagnostics = DiagnosticsModel()
    @State private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            StoreRoot(model: model, registration: registration)
                .task {
                    await registration.ensureEnabled()
                    await model.start()
                    await diagnostics.connect()
                }
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            StoreCommands()
            DiagnosticsCommands()
        }

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(model: diagnostics)
        }
        .defaultSize(width: 980, height: 640)

        Settings { SettingsView(model: model) }
    }

    private static func makeModel() -> StoreModel {
        let manifest = Bundle.main.url(forResource: "GuestImage", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(GuestImageManifest.self, from: $0) }
        let template = Bundle.main.resourceURL!.appending(path: "CrosswindAppStub.app")
        return StoreModel(
            manifest: manifest, paths: .standard, stubs: StubInstaller(template: template),
            opener: { url in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            })
    }
}
