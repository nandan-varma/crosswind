// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

// The four onboarding screens. Each is a column: a hero, a headline, the content, then one clear action.

struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HeroIcon()
            VStack(spacing: 8) {
                Text("Welcome to Crosswind")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Run Linux apps on your Mac, as real Mac apps.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                Feature(
                    symbol: "macwindow.on.rectangle", tint: .blue, title: "Native windows",
                    detail: "Every app gets its own window, Dock icon and Cmd-Tab entry.")
                Feature(
                    symbol: "square.grid.2x2.fill", tint: .purple, title: "Thousands of apps",
                    detail: "Browse and install apps from Flathub, with updates in one place.")
                Feature(
                    symbol: "lock.shield.fill", tint: .green, title: "Contained",
                    detail: "Apps run in a virtual machine and only see the folders you share.")
            }
            .padding(.vertical, 8)
            Button("Continue", action: onContinue)
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown while macOS waits for the user to turn on Crosswind's background item. It leaves by itself when they do.
struct AllowServiceStep: View {
    let registration: HostRegistration

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Allow Crosswind in the background")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("A small background service runs Linux apps, so they keep running when you close the store.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                NumberedStep(number: 1, text: "Open Login Items & Extensions")
                NumberedStep(number: 2, text: "Find Crosswind under Allow in the Background")
                NumberedStep(number: 3, text: "Turn it on")
            }
            Button("Open Login Items Settings") { registration.openSettings() }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to turn it on…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if let failure = registration.failure {
                Text(verbatim: failure).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout.bold())
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.18), in: Circle())
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(number): \(text)"))
    }
}

/// The Linux environment downloads and the catalog loads. Real progress, and tips to read meanwhile.
struct SettingUpStep: View {
    let phase: StoreModel.Phase
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            HeroIcon(size: 104)
            if case .failed(let message) = phase {
                failure(message)
            } else {
                progress
                TipRotator()
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 14) {
            Text(headline)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .contentTransition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 320)
                    .animation(.smooth, value: fraction)
                Text("\(Int((fraction * 100).rounded())) percent")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } else {
                ProgressView().controlSize(.large)
            }
            if isFirstDownload {
                Text("This only happens the first time.").foregroundStyle(.secondary)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Setup didn't finish").font(.system(size: 26, weight: .bold, design: .rounded))
            Text(verbatim: message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try Again", action: retry).buttonStyle(.glassProminent).controlSize(.large)
        }
    }

    private var headline: LocalizedStringKey {
        switch phase {
        case .connecting: "Starting Crosswind…"
        case .installingImage: "Downloading the Linux environment"
        case .updatingImage: "Updating the Linux environment"
        case .loadingCatalog: "Loading the app catalog"
        case .ready, .failed: ""
        }
    }

    private var fraction: Double? {
        switch phase {
        case .installingImage(let value), .updatingImage(let value): value
        default: nil
        }
    }

    private var isFirstDownload: Bool {
        if case .installingImage = phase { true } else { false }
    }
}

/// A short tip that changes every few seconds while setup runs.
private struct TipRotator: View {
    private static let tips: [(symbol: String, text: LocalizedStringKey)] = [
        ("command", "The Command key works as Control in Linux apps, so ⌘C and ⌘V just work."),
        ("dock.rectangle", "Every Linux app gets its own Dock icon, window and Cmd-Tab entry."),
        ("folder.badge.plus", "Apps only see the folders you share. Add them in Settings."),
        ("menubar.rectangle", "Apps with a tray icon, like chat clients, show it in your menu bar."),
        ("doc.on.clipboard", "Copy and paste work both ways between your Mac and Linux apps."),
    ]

    @State private var index = 0

    var body: some View {
        let tip = Self.tips[index]
        Label {
            Text(tip.text)
        } icon: {
            Image(systemName: tip.symbol).foregroundStyle(.tint)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: 420, minHeight: 44)
        .id(index)
        .transition(.opacity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.smooth) { index = (index + 1) % Self.tips.count }
            }
        }
    }
}

/// The last screen: a handful of good first apps to install on the spot, then into the store.
struct ReadyStep: View {
    let model: StoreModel
    let onFinish: () -> Void

    /// Apps that show off what Crosswind runs, in the order offered. Only those in the catalog are shown.
    private static let starterIDs = [
        "org.videolan.VLC", "org.gimp.GIMP", "com.vscodium.codium", "org.libreoffice.LibreOffice",
        "org.inkscape.Inkscape", "org.telegram.desktop", "org.kde.kate", "org.chromium.Chromium",
    ]

    private var starters: [CatalogApp] {
        Self.starterIDs.compactMap { model.app($0) }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("You're all set")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Pick an app to start with, or explore the store.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if !starters.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    ForEach(starters) { app in
                        StarterTile(app: app, model: model)
                    }
                }
            }
            Button("Start Exploring", action: onFinish)
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct StarterTile: View {
    let app: CatalogApp
    let model: StoreModel

    var body: some View {
        VStack(spacing: 10) {
            AppIconView(app: app, size: 56)
            Text(verbatim: app.name).font(.headline).lineLimit(1)
            ActionButton(appID: app.id, model: model)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: 18)
    }
}
