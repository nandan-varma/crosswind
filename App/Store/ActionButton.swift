// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The App Store–style primary button for one app: Get, a progress ring while working, Update, or Open.
struct ActionButton: View {
    let appID: String
    let model: StoreModel

    private var name: String { model.app(appID)?.name ?? appID }

    var body: some View {
        if let operation = model.operations[appID], operation.failure == nil {
            ProgressRing(fraction: operation.fraction).help(operation.detail)
        } else if let installed = model.installed[appID] {
            if installed.updateAvailable {
                Button("Update") { Task { await model.update(appID) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Update \(name)")
            } else {
                Button("Open") { Task { await model.open(appID) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open \(name)")
            }
        } else {
            Button("Get") { Task { await model.install(appID) } }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Get \(name)")
        }
    }
}

private struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ProgressView(value: max(fraction, 0.02))
            .progressViewStyle(.circular)
            .controlSize(.small)
            .frame(width: 28, height: 28)
    }
}
