// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// Apps with a newer version in the catalog, with Update All and per-app updates and release notes.
struct UpdatesView: View {
    let model: StoreModel

    var body: some View {
        let records = updatable
        if records.isEmpty {
            ContentUnavailableView {
                Label("Everything is up to date", systemImage: "checkmark.circle")
            } description: {
                Text("Updates for your installed apps appear here.")
            }
        } else {
            List {
                Section {
                    header(count: records.count)
                }
                Section {
                    ForEach(records, id: \.appID) { record in
                        row(for: record)
                    }
                }
            }
        }
    }

    private var updatable: [Crosswind_Control_InstalledApp] {
        model.installed.values.filter(\.updateAvailable).sorted { $0.appID < $1.appID }
    }

    /// The batch update runs under the empty app id; it is in flight while any operation is.
    private var batch: AppOperation? { model.operations[""] }

    private var isBusy: Bool { model.operations.values.contains { $0.failure == nil } }

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Updates Available").font(.headline)
                // Plural variations for "1 app" and "N apps" live in Localizable.xcstrings.
                Text("\(count) apps can be updated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let batch, batch.failure == nil {
                ProgressView(value: batch.fraction)
                    .frame(width: 160)
                    .help(batch.detail)
                    .accessibilityLabel(String(localized: "Updating all apps"))
            } else if let failure = batch?.failure {
                Text(failure).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            Button("Update All") { Task { await model.updateAll() } }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }

    private func row(for record: Crosswind_Control_InstalledApp) -> some View {
        let app = libraryApp(for: record, in: model)
        let latest = app.releases.first
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                LibraryAppIcon(app: app, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text(versionLine(installed: record.version, latest: latest?.version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ActionButton(appID: app.id, model: model)
            }
            if let failure = model.operations[app.id]?.failure {
                Text(verbatim: failure).font(.caption).foregroundStyle(.red)
            }
            if let notes = latest?.description, !notes.isEmpty {
                DisclosureGroup("Release Notes") {
                    Text(verbatim: notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    private func versionLine(installed: String, latest: String?) -> String {
        guard let latest, !latest.isEmpty else { return String(localized: "Version \(installed)") }
        return String(localized: "Version \(installed) → \(latest)")
    }
}
