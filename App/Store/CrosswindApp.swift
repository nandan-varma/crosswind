// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI

@main
struct CrosswindApp: App {
    @State private var model = Self.makeModel()

    var body: some Scene {
        WindowGroup {
            StoreRoot(model: model)
                .task {
                    HostRegistration.register()
                    await model.start()
                }
        }
        .defaultSize(width: 1080, height: 720)
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
