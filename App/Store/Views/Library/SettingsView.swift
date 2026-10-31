// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import ServiceManagement
import SwiftUI

/// The settings window, for a SwiftUI `Settings` scene.
struct SettingsView: View {
    let model: StoreModel

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .scenePadding()
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.Key.commandActsAsControl, store: Preferences.suite) private var commandActsAsControl = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Toggle("Command key acts as Control", isOn: $commandActsAsControl)
                .help("Use the Command key for shortcuts that Linux apps expect on Control.")
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}

private struct StorageSettings: View {
    private let directory = GuestPaths.standard.supportDirectory
    @State private var size: String?

    var body: some View {
        Form {
            LabeledContent("Space used") {
                Text(size ?? String(localized: "Calculating…"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Location") {
                Text(directory.path(percentEncoded: false))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("Reset Linux environment…") {}
                .disabled(true)
                .help("Coming soon")
        }
        .formStyle(.grouped)
        .task { size = await Self.measure(directory) }
    }

    /// Walks the folder off the main actor and formats the allocated size of its files.
    private static func measure(_ url: URL) async -> String {
        let bytes = await Task.detached(priority: .utility) { allocatedSize(of: url) }.value
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct AboutSettings: View {
    private static let license = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")
    private static let repository = URL(string: "https://github.com/nandan-varma/crosswind")

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        Form {
            LabeledContent("Version", value: "\(version) (\(build))")
            if let license = Self.license {
                Link("AGPL-3.0 License", destination: license)
            }
            if let repository = Self.repository {
                Link("Source on GitHub", destination: repository)
            }
        }
        .formStyle(.grouped)
    }
}

/// Total allocated size of the regular files under `url`.
private func allocatedSize(of url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
    var total: Int64 = 0
    while let file = enumerator.nextObject() as? URL {
        guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
        total += Int64(values.totalFileAllocatedSize ?? 0)
    }
    return total
}
