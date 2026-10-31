// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI

/// The folders the user shares with Linux apps. Nothing is shared until a folder is added.
struct SharedFoldersSettings: View {
    @State private var folders = (try? SharedFolders.load(from: SharedFolders.defaultFile)) ?? SharedFolders()
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Text(
                    "Linux apps can read and write everything in shared folders. "
                        + "Nothing is shared until you add a folder."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section {
                if folders.folders.isEmpty {
                    Text("No shared folders").foregroundStyle(.secondary)
                }
                ForEach(folders.folders, id: \.name) { folder in
                    LabeledContent {
                        HStack {
                            Toggle("Read only", isOn: readOnlyBinding(folder))
                            Button(role: .destructive) {
                                remove(folder)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop sharing this folder")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            Section {
                Button("Add Folder…", action: addFolder)
                Text("Shared folders appear in Linux apps under /mnt/mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func readOnlyBinding(_ folder: SharedFolder) -> Binding<Bool> {
        Binding(
            get: { folder.readOnly },
            set: { readOnly in
                folders.setReadOnly(readOnly, name: folder.name)
                save()
            })
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Share"
        panel.message = "Choose a folder to share with Linux apps."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folders.add(path: url.path)
        save()
    }

    private func remove(_ folder: SharedFolder) {
        folders.remove(name: folder.name)
        save()
    }

    private func save() {
        do {
            try folders.save(to: SharedFolders.defaultFile)
            failure = nil
        } catch {
            failure = "Could not save the shared folders: \(error.localizedDescription)"
        }
    }
}
