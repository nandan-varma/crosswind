// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// Shows the store once the Linux environment is ready, and the setup progress or failure until then.
struct StoreRoot: View {
    let model: StoreModel
    let registration: HostRegistration

    var body: some View {
        if registration.needsApproval {
            ContentUnavailableView {
                Label("Allow Crosswind in the background", systemImage: "checkmark.shield")
            } description: {
                Text(
                    "Crosswind runs Linux apps through a small background service. Turn on Crosswind in System Settings › General › Login Items & Extensions."
                )
            } actions: {
                Button("Open Login Items Settings") { registration.openSettings() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .ready:
            StoreShell(model: model)
        case .failed(let message):
            ContentUnavailableView {
                Label("Crosswind couldn't start", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.start() } }
                    .buttonStyle(.borderedProminent)
            }
        default:
            SetupView(phase: model.phase)
        }
    }
}

private struct SetupView: View {
    let phase: StoreModel.Phase

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            if case .installingImage(let fraction) = phase {
                ProgressView(value: fraction).frame(width: 240)
            } else {
                ProgressView().controlSize(.small)
            }
            Text("This only happens the first time.").foregroundStyle(.secondary).font(.callout)
                .opacity(isFirstRunStep ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isFirstRunStep: Bool {
        if case .installingImage = phase { true } else { false }
    }

    private var title: String {
        switch phase {
        case .connecting: "Connecting…"
        case .installingImage: "Setting up Linux apps"
        case .loadingCatalog: "Loading apps"
        case .ready, .failed: ""
        }
    }
}
