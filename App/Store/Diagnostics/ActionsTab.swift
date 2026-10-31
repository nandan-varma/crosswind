// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import SwiftUI
import UniformTypeIdentifiers

struct ActionsTab: View {
    let model: DiagnosticsModel

    @State private var exported: URL?
    @State private var exportError: String?
    @State private var exporting = false

    var body: some View {
        Form {
            Section("Environment") {
                HStack {
                    Button("Start Environment") { Task { await model.run(.startVm(.init())) } }
                    Button("Stop Environment") { Task { await model.run(.stopVm(.init())) } }
                }
            }
            Section("Support") {
                Button("Export Diagnostic Bundle…") { Task { await export() } }
                    .disabled(exporting)
                if let exported {
                    LabeledContent("Saved to") {
                        Button(exported.lastPathComponent) {
                            NSWorkspace.shared.activateFileViewerSelecting([exported])
                        }
                    }
                }
                if let exportError {
                    Text(verbatim: exportError).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func export() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "crosswind-diagnostics-\(Self.stamp()).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        defer { exporting = false }
        do {
            try await model.exportBundle(to: url)
            exported = url
            exportError = nil
        } catch {
            exportError = String(localized: "Export failed: \(String(describing: error))")
        }
    }

    private static func stamp() -> String {
        Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
    }
}
