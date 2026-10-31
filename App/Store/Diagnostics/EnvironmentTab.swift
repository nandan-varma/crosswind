// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

struct EnvironmentTab: View {
    let model: DiagnosticsModel

    var body: some View {
        Form {
            Section("Virtual machine") {
                LabeledContent("Phase", value: phaseName)
                if !model.phaseDetail.isEmpty {
                    LabeledContent("Detail", value: model.phaseDetail)
                }
                LabeledContent("Uptime") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(uptime(at: context.date))
                            .monospacedDigit()
                    }
                }
                LabeledContent("Guest kernel and hostname") {
                    Text("not exposed by the control protocol")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Running apps") {
                if model.runningApps.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(model.runningApps, id: \.self) { Text(verbatim: $0) }
                }
            }
            Section("Host agent") {
                if let process = model.agentProcess {
                    LabeledContent("Resident memory", value: Self.bytes(process.residentBytes))
                    let cpu = process.cpuPercent.map { String(format: "%.1f%%", $0) }
                    LabeledContent("CPU", value: cpu ?? String(localized: "measuring"))
                } else {
                    Text("CrosswindHost is not running").foregroundStyle(.secondary)
                }
                LabeledContent(
                    "Connection",
                    value: model.isConnected ? String(localized: "connected") : String(localized: "not connected"))
            }
            if let error = model.lastError {
                Section("Last error") {
                    Text(verbatim: error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var phaseName: String {
        switch model.phase {
        case .stopped: String(localized: "stopped")
        case .starting: String(localized: "starting")
        case .running: String(localized: "running")
        case .stopping: String(localized: "stopping")
        case .failed: String(localized: "failed")
        case .UNRECOGNIZED: String(localized: "unknown")
        }
    }

    private func uptime(at date: Date) -> String {
        guard let since = model.runningSince else { return "-" }
        let seconds = Int(date.timeIntervalSince(since))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}
