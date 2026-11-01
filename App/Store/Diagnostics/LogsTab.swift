// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI

struct LogsTab: View {
    let model: DiagnosticsModel

    @State private var search = ""
    @State private var source = "All"
    @State private var minimumLevel = LevelFilter.debug
    @State private var launchID = "All"
    @State private var paused = false
    @State private var frozen: [LogEntry] = []
    @State private var autoScroll = true
    @State private var selection: LogEntry.ID?

    enum LevelFilter: Int, CaseIterable, Identifiable {
        case error = 3
        case warning = 4
        case info = 6
        case debug = 7
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .error: String(localized: "Error")
            case .warning: String(localized: "Warning and up")
            case .info: String(localized: "Info and up")
            case .debug: String(localized: "All levels")
            }
        }
    }

    private var live: [LogEntry] { Array(model.logs.entries) }
    private var base: [LogEntry] { paused ? frozen : live }

    private var sources: [String] {
        ["All"] + Array(Set(base.map(\.source))).sorted()
    }

    private var launches: [String] {
        ["All"] + Array(Set(base.map(\.launchID).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [LogEntry] {
        base.filter { entry in
            (source == "All" || entry.source == source)
                && (launchID == "All" || entry.launchID == launchID)
                && entry.level <= Int32(minimumLevel.rawValue)
                && (search.isEmpty || entry.text.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Filter text", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Picker("Source", selection: $source) {
                    ForEach(sources, id: \.self) { Text(verbatim: optionLabel($0)).tag($0) }
                }
                .frame(maxWidth: 200)
                Picker("Level", selection: $minimumLevel) {
                    ForEach(LevelFilter.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 170)
                Picker("Launch", selection: $launchID) {
                    ForEach(launches, id: \.self) { Text(verbatim: optionLabel($0)).tag($0) }
                }
                .frame(maxWidth: 170)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .help(String(localized: "Keep the newest log line selected while new lines arrive"))
                Toggle("Pause", isOn: $paused)
                    .help(String(localized: "Stop the list from updating"))
                    .onChange(of: paused) { _, isPaused in
                        if isPaused { frozen = live }
                    }
                Button("Copy") { copyVisible() }
                    .help(String(localized: "Copy the visible log lines"))
                    .disabled(filtered.isEmpty)
                Button("Load Host Logs") { Task { await model.loadHostLogs() } }
                    .help(String(localized: "Load the host agent's log lines"))
            }
            Table(filtered, selection: $selection) {
                TableColumn("Time") { entry in
                    Text(entry.time, format: .dateTime.hour().minute().second())
                }
                .width(min: 70, ideal: 80, max: 90)
                TableColumn("Source") { Text(verbatim: $0.source) }
                    .width(min: 90, ideal: 130)
                TableColumn("Level") { Text(verbatim: $0.levelName) }
                    .width(min: 60, ideal: 70, max: 80)
                TableColumn("Launch") { Text(verbatim: $0.launchID) }
                    .width(min: 60, ideal: 80)
                TableColumn("Message") { Text(verbatim: $0.text).textSelection(.enabled) }
            }
            .font(.system(.body, design: .monospaced))
            .onChange(of: filtered.count) { _, _ in
                guard autoScroll, !paused, let last = filtered.last else { return }
                selection = last.id
            }
        }
        .padding()
        .onAppear { if paused { frozen = live } }
    }

    /// The "All" sentinel is shown localized; every other option is data and shown as is.
    private func optionLabel(_ value: String) -> String {
        value == "All" ? String(localized: "All") : value
    }

    private func copyVisible() {
        let text = filtered.map { entry in
            "\(entry.time.formatted(.iso8601)) [\(entry.source)] \(entry.levelName) \(entry.launchID) \(entry.text)"
        }
        .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
