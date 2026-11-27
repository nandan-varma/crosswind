// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The App Store–style primary button for one app: Get, a progress ring while working, Update, or Open.
struct ActionButton: View {
    let appID: String
    let model: StoreModel

    private var name: String { model.app(appID)?.name ?? appID }

    var body: some View {
        content.animation(.smooth(duration: 0.3), value: state)
    }

    /// What the button shows, so a change between states animates.
    private var state: String {
        if let operation = model.operations[appID], operation.failure == nil { return "working" }
        if let installed = model.installed[appID] { return installed.updateAvailable ? "update" : "open" }
        return "get"
    }

    @ViewBuilder private var content: some View {
        if let operation = model.operations[appID], operation.failure == nil {
            ProgressRing(name: name, fraction: operation.fraction)
                .help(operation.detail)
        } else if let installed = model.installed[appID] {
            if installed.updateAvailable {
                Button("Update") { Task { await model.update(appID) } }
                    .buttonStyle(.glassProminent)
                    .help(String(localized: "Update \(name)"))
                    .accessibilityLabel(Text("Update \(name)"))
            } else {
                Button("Open") { Task { await model.open(appID) } }
                    .buttonStyle(.glass)
                    .help(String(localized: "Open \(name)"))
                    .accessibilityLabel(Text("Open \(name)"))
            }
        } else {
            Button("Get") { Task { await model.install(appID) } }
                .buttonStyle(.glassProminent)
                .help(String(localized: "Get \(name)"))
                .accessibilityLabel(Text("Get \(name)"))
        }
    }
}

/// Shown while an operation runs. Reads as "Installing <name>, <percent>".
private struct ProgressRing: View {
    let name: String
    let fraction: Double

    var body: some View {
        ProgressView(value: max(fraction, 0.02))
            .progressViewStyle(.circular)
            .controlSize(.small)
            .frame(width: 28, height: 28)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(Text("Working on \(name)"))
            .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}
