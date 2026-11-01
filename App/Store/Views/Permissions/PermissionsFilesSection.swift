// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The Files group: the common folders the app may reach, and folders the user adds by path.
struct PermissionsFilesSection: View {
    let editor: PermissionsModel
    @State private var customPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(PermissionCatalog.filesystemPresets) { preset in
                        presetRow(preset)
                    }
                    Divider()
                    Text("Other Folders")
                        .font(.subheadline.bold())
                    ForEach(customAccess, id: \.path) { access in
                        customRow(access)
                    }
                    addCustomRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var customAccess: [FilesystemAccess] {
        let presets = Set(PermissionCatalog.filesystemPresets.map(\.path))
        return editor.draft.fileAccess.filter { !presets.contains($0.path) }
    }

    private func presetRow(_ preset: FilesystemPreset) -> some View {
        let access = editor.draft.access(to: preset.path)
        let changed = editor.draft.isChanged(path: preset.path, from: editor.baseline)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(
                isOn: Binding(
                    get: { access != nil },
                    set: { on in
                        editor.edit { permissions in
                            if on {
                                permissions.setAccess(FilesystemAccess(path: preset.path))
                            } else {
                                permissions.removeAccess(to: preset.path)
                            }
                        }
                    })
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Label {
                            Text(preset.title)
                        } icon: {
                            Image(systemName: preset.symbol)
                                .foregroundStyle(preset.isBroad ? .orange : .primary)
                        }
                        if changed { PermissionChangedBadge() }
                    }
                    Text(preset.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if preset.isBroad { PermissionBroadWarning() }
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel(Text(preset.title))
            .accessibilityHint(Text(preset.detail))
            if let access {
                modePicker(access, label: String(localized: preset.title))
                    .padding(.leading, 28)
            }
        }
    }

    private func customRow(_ access: FilesystemAccess) -> some View {
        HStack(spacing: 10) {
            Label {
                Text(verbatim: access.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "folder")
            }
            Spacer()
            modePicker(access, label: access.path)
            Button(role: .destructive) {
                editor.edit { $0.removeAccess(to: access.path) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Stop sharing this folder with the app"))
            .accessibilityLabel(Text("Remove \(access.path)"))
        }
    }

    private var addCustomRow: some View {
        HStack(spacing: 10) {
            TextField("Folder path, for example ~/Projects", text: $customPath)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addCustomPath)
                .accessibilityLabel(Text("Folder path"))
            Button("Add Folder", systemImage: "plus", action: addCustomPath)
                .disabled(!FilesystemAccess.isValidCustomPath(customPath))
        }
    }

    private func addCustomPath() {
        let path = customPath.trimmingCharacters(in: .whitespaces)
        guard FilesystemAccess.isValidCustomPath(path) else { return }
        if editor.draft.access(to: path) == nil {
            editor.edit { $0.setAccess(FilesystemAccess(path: path)) }
        }
        customPath = ""
    }

    private func modePicker(_ access: FilesystemAccess, label: String) -> some View {
        Picker(
            selection: Binding(
                get: { access.mode },
                set: { mode in editor.edit { $0.setAccess(FilesystemAccess(path: access.path, mode: mode)) } })
        ) {
            ForEach(FilesystemAccess.Mode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            Text("Access")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel(Text("Access for \(label)"))
    }
}
