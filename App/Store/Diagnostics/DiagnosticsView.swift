// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The Diagnostics window: logs, environment, windows and performance, and actions.
struct DiagnosticsView: View {
    let model: DiagnosticsModel

    var body: some View {
        TabView {
            LogsTab(model: model)
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
            EnvironmentTab(model: model)
                .tabItem { Label("Environment", systemImage: "desktopcomputer") }
            WindowsTab(model: model)
                .tabItem { Label("Windows & Performance", systemImage: "chart.xyaxis.line") }
            ActionsTab(model: model)
                .tabItem { Label("Actions", systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { await model.connect() }
    }
}

/// Opens the Diagnostics window with Cmd-Opt-D from the Window menu.
struct DiagnosticsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Diagnostics") { openWindow(id: "diagnostics") }
                .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}
