// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The apps installed in the Linux environment, with open, reveal and uninstall actions.
struct InstalledView: View {
    let model: StoreModel
    @State private var uninstalling: CatalogApp?

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("No Installed Apps", systemImage: "square.stack.3d.up")
            } description: {
                Text("Apps you get from the store appear here.")
            }
        } else {
            List(entries, id: \.appID) { record in
                row(for: record)
            }
            .confirmationDialog(
                uninstalling.map { String(localized: "Uninstall \($0.name)?") } ?? "",
                isPresented: Binding(
                    get: { uninstalling != nil },
                    set: { if !$0 { uninstalling = nil } }),
                titleVisibility: .visible,
                presenting: uninstalling
            ) { app in
                Button("Uninstall", role: .destructive) { Task { await model.uninstall(app.id) } }
                Button("Uninstall and Delete Data", role: .destructive) {
                    Task { await model.uninstall(app.id, deleteData: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Deleting the data also removes the app's settings and files in the Linux environment.")
            }
        }
    }

    private var entries: [Crosswind_Control_InstalledApp] {
        model.installed.values.sorted { lhs, rhs in
            libraryApp(for: lhs, in: model).name.localizedStandardCompare(libraryApp(for: rhs, in: model).name)
                == .orderedAscending
        }
    }

    private func row(for record: Crosswind_Control_InstalledApp) -> some View {
        let app = libraryApp(for: record, in: model)
        return HStack(spacing: 12) {
            LibraryAppIcon(app: app, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                HStack(spacing: 6) {
                    Text("Version \(record.version)")
                    if model.isRunning(app.id) {
                        Label {
                            Text("Running")
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ActionButton(appID: app.id, model: model)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Open") { Task { await model.open(app.id) } }
            Button("Show in Finder") { revealStub(for: app) }
            Divider()
            Button("Uninstall…", role: .destructive) { uninstalling = app }
        }
    }
}
