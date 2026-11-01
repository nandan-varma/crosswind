// SPDX-License-Identifier: AGPL-3.0-or-later
import Charts
import CrosswindKit
import SwiftUI

struct WindowsTab: View {
    let model: DiagnosticsModel

    @State private var selected: UInt32?

    private var selectedStats: WindowStats? {
        model.windows.first { $0.id == selected } ?? model.windows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.windows.isEmpty {
                ContentUnavailableView(
                    "No guest windows", systemImage: "macwindow",
                    description: Text("Windows appear here while an app is open."))
            } else {
                Table(model.windows, selection: $selected) {
                    TableColumn("ID") { Text(verbatim: "\($0.id)") }.width(min: 40, ideal: 50, max: 60)
                    TableColumn("App") { Text(verbatim: $0.info.appID) }
                    TableColumn("Size") { Text(verbatim: "\($0.info.width)x\($0.info.height)") }
                        .width(min: 80, ideal: 100)
                    TableColumn("Scale") { Text(verbatim: String(format: "%.2fx", Double($0.info.scale120) / 120)) }
                        .width(min: 60, ideal: 70)
                    TableColumn("Frames") { Text(verbatim: "\($0.info.frames)").monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("FPS") { Text(verbatim: String(format: "%.1f", $0.framesPerSecond)).monospacedDigit() }
                        .width(min: 50, ideal: 60)
                    TableColumn("Input to frame") {
                        Text(verbatim: String(format: "%.1f ms", $0.info.lastInputToFrameMs))
                    }
                    .width(min: 100, ideal: 120)
                }
                .frame(minHeight: 180)
                if let stats = selectedStats {
                    Text("Input-to-frame latency, \(stats.info.appID), last \(stats.latencyHistory.count) polls")
                        .font(.headline)
                    Chart {
                        ForEach(Array(stats.latencyHistory.enumerated()), id: \.offset) { index, latency in
                            LineMark(x: .value("Poll", index), y: .value("ms", latency))
                        }
                    }
                    .chartYAxisLabel("ms")
                    .frame(height: 160)
                    .accessibilityLabel(Text("Input-to-frame latency chart"))
                }
            }
        }
        .padding()
        .onAppear { model.setWindowsVisible(true) }
        .onDisappear { model.setWindowsVisible(false) }
    }
}
