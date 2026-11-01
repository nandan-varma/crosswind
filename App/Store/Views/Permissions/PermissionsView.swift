// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The app's Flatpak permissions in plain language, shown on its page once it is installed.
struct PermissionsView: View {
    let appID: String
    let store: StoreModel
    @State private var editor: PermissionsModel
    @State private var customPath = ""

    init(appID: String, store: StoreModel) {
        self.appID = appID
        self.store = store
        _editor = State(initialValue: PermissionsModel(appID: appID, store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(
                "Permissions decide what this app can reach outside its window. "
                    + "Changes apply the next time the app starts."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            statusRow
            restartRow
            switch editor.load {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .failed(let message):
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.red)
            case .loaded:
                ForEach(PermissionCatalog.grouped(options), id: \.group) { group in
                    optionGroup(group.group, group.options)
                }
                PermissionsFilesSection(editor: editor)
            }
            if let failure = editor.failure {
                Text(verbatim: failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await editor.fetch() }
    }

    private var options: [PermissionOption] {
        PermissionCatalog.options(for: editor.draft, defaults: editor.baseline)
    }

    // MARK: Status

    @ViewBuilder
    private var statusRow: some View {
        if editor.defaults == nil, editor.load == .loaded {
            Label(
                "This version of Crosswind cannot tell the app's defaults from your changes.",
                systemImage: "questionmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if editor.load == .loaded {
            HStack(spacing: 12) {
                if editor.changeCount == 0 {
                    Label("Using the app's default permissions", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "\(editor.changeCount) changed from the app's defaults", systemImage: "pencil.circle"
                    )
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if editor.beforeReset != nil {
                    Button("Undo Reset", systemImage: "arrow.uturn.backward") { editor.undoReset() }
                }
                Button("Reset to Defaults", systemImage: "arrow.counterclockwise") { editor.resetToDefaults() }
                    .disabled(!editor.canReset)
                    .accessibilityHint(Text("Removes every change you made to this app's permissions"))
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var restartRow: some View {
        if store.isRunning(appID) {
            HStack(spacing: 12) {
                Label("The app is running with its previous permissions.", systemImage: "info.circle")
                    .font(.callout)
                Spacer()
                Button("Restart App", systemImage: "arrow.clockwise") {
                    Task { await editor.restart() }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    // MARK: Groups

    private func optionGroup(_ group: PermissionOption.Group, _ options: [PermissionOption]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(for: group))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(options) { option in
                        optionRow(option)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func title(for group: PermissionOption.Group) -> LocalizedStringResource {
        switch group {
        case .network: "Network"
        case .windowing: "Windows and Communication"
        case .sound: "Sound"
        case .devices: "Devices"
        case .files: "Files"
        case .features: "Features"
        case .other: "Other"
        }
    }

    private func optionRow(_ option: PermissionOption) -> some View {
        let changed = editor.draft.isChanged(option, from: editor.baseline)
        return Toggle(
            isOn: Binding(
                get: { editor.draft.isOn(option) },
                set: { on in editor.edit { $0.set(option, on: on) } })
        ) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Label {
                        Text(option.title)
                    } icon: {
                        Image(systemName: option.symbol)
                            .foregroundStyle(option.isBroad ? .orange : .primary)
                    }
                    if changed { PermissionChangedBadge() }
                }
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if option.isBroad { PermissionBroadWarning() }
            }
        }
        .toggleStyle(.switch)
        .accessibilityLabel(Text(option.title))
        .accessibilityHint(Text(option.detail))
        .accessibilityValue(changed ? Text("Changed from the app's default") : Text(""))
    }

}
