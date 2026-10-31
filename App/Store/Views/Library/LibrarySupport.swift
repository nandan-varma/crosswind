// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI

/// The catalog entry for an installed app, or a stand-in built from the installed record when the catalog lacks it.
@MainActor
func libraryApp(for record: Crosswind_Control_InstalledApp, in model: StoreModel) -> CatalogApp {
    if let app = model.app(record.appID) { return app }
    var app = CatalogApp()
    app.id = record.appID
    app.name = record.name.isEmpty ? record.appID : record.name
    return app
}

/// Shows the stub bundle for `app` in Finder, or the stub folder when the bundle is missing.
@MainActor
func revealStub(for app: CatalogApp) {
    let bundle = StubInstaller.defaultDirectory.appending(path: "\(app.name).app", directoryHint: .isDirectory)
    let target = FileManager.default.fileExists(atPath: bundle.path) ? bundle : StubInstaller.defaultDirectory
    NSWorkspace.shared.activateFileViewerSelecting([target])
}

/// Stand-in for `AppIconView` (App/Store/Views/) until it lands; swap the body of this view for it.
struct LibraryAppIcon: View {
    let app: CatalogApp
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
