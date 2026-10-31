// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import Darwin
import ServiceManagement
import SwiftUI

/// The settings window, for a SwiftUI `Settings` scene.
struct SettingsView: View {
    let model: StoreModel

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            EnvironmentSettings(model: model)
                .tabItem { Label("Environment", systemImage: "cpu") }
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            SharedFoldersSettings(model: model)
                .tabItem { Label("Shared Folders", systemImage: "folder.badge.person.crop") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .scenePadding()
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preferences.Key.commandActsAsControl, store: Preferences.suite) private var commandActsAsControl = true
    @AppStorage(Preferences.Key.clipboardSync, store: Preferences.suite) private var clipboardSync = true
    @AppStorage(Preferences.Key.microphoneEnabled, store: Preferences.suite) private var microphoneEnabled = false
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
            Toggle("Share the clipboard with Linux apps", isOn: $clipboardSync)
                .help("Text and images are shared while a Crosswind app is in front.")
            Toggle("Allow Linux apps to use the microphone", isOn: $microphoneEnabled)
            Text("Off by default. Applies the next time the Linux environment starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

private struct EnvironmentSettings: View {
    let model: StoreModel
    @AppStorage(Preferences.Key.cpuCount, store: Preferences.suite) private var cpuCount = Preferences.defaultCPUCount
    @AppStorage(Preferences.Key.memoryGiB, store: Preferences.suite) private var memoryGiB = Preferences
        .defaultMemoryGiB
    @AppStorage(Preferences.Key.idleTimeoutMinutes, store: Preferences.suite)
    private var idleMinutes = Preferences.defaultIdleTimeoutMinutes
    @State private var working = false
    @State private var confirmReset = false
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Stepper(value: $cpuCount, in: Preferences.cpuRange) {
                    LabeledContent("Virtual CPUs", value: "\(cpuCount)")
                }
                LabeledContent("Memory") {
                    HStack {
                        Slider(
                            value: memoryBinding,
                            in: Double(Preferences.memoryRange.lowerBound)...Double(Preferences.memoryRange.upperBound),
                            step: 1
                        )
                        .frame(width: 180)
                        Text("\(memoryGiB) GiB").monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                }
                Stepper(value: $idleMinutes, in: Preferences.idleTimeoutRange) {
                    LabeledContent(
                        "Stop when idle",
                        value: idleMinutes == 0
                            ? String(localized: "Never") : String(localized: "After \(idleMinutes) min"))
                }
            } footer: {
                Text(
                    "Applies the next time the environment starts. Stopping it frees its memory; "
                        + "apps start it again when you open them.")
            }
            Section {
                Button("Restart Environment") { run { try await model.restartEnvironment() } }
                    .disabled(working)
                Button("Reset Linux Environment…", role: .destructive) { confirmReset = true }
                    .disabled(working)
            }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset the Linux environment?", isPresented: $confirmReset, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { run { try await model.resetEnvironment() } }
        } message: {
            Text("Every installed app and its data is deleted. This cannot be undone.")
        }
    }

    private var memoryBinding: Binding<Double> {
        Binding(get: { Double(memoryGiB) }, set: { memoryGiB = Int($0) })
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        failure = nil
        Task {
            do {
                try await action()
            } catch {
                failure = error.localizedDescription
            }
            working = false
        }
    }
}

private struct StorageSettings: View {
    private let directory = GuestPaths.standard.supportDirectory
    @State private var size: String?
    @State private var disk: String?

    var body: some View {
        Form {
            LabeledContent("Space used") {
                Text(size ?? String(localized: "Calculating…"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Data disk") {
                Text(disk ?? String(localized: "Not created yet"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Location") {
                Text(directory.path(percentEncoded: false))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .task {
            size = await Self.measure(directory)
            disk = await Self.dataDiskUsage(GuestPaths.standard.dataDisk)
        }
    }

    /// Walks the folder off the main actor and formats the allocated size of its files.
    private static func measure(_ url: URL) async -> String {
        let bytes = await Task.detached(priority: .utility) { allocatedSize(of: url) }.value
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "allocated of capacity" for the sparse data disk: blocks actually written against its size.
    private static func dataDiskUsage(_ url: URL) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            var info = stat()
            guard stat(url.path(percentEncoded: false), &info) == 0 else { return nil }
            let allocated = Int64(info.st_blocks) * 512
            let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
            return "\(format(allocated)) of \(format(Int64(info.st_size)))"
        }.value
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
