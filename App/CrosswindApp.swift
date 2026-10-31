// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

@main
struct CrosswindApp: App {
    var body: some Scene {
        WindowGroup {
            StoreShell()
        }
        .defaultSize(width: 980, height: 640)
    }
}

enum StoreSection: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case installed = "Installed"
    case updates = "Updates"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .discover: "square.grid.2x2"
        case .installed: "square.and.arrow.down"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var emptyMessage: String {
        switch self {
        case .discover: "The Flathub catalog is not available yet."
        case .installed: "Apps you install will appear here."
        case .updates: "Updates for installed apps will appear here."
        }
    }
}

struct StoreShell: View {
    @State private var selection: StoreSection? = .discover

    var body: some View {
        NavigationSplitView {
            List(StoreSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
            }
            .navigationTitle("Crosswind")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            let section = selection ?? .discover
            ContentUnavailableView(
                section.rawValue,
                systemImage: section.systemImage,
                description: Text(section.emptyMessage)
            )
            .navigationTitle(section.rawValue)
        }
    }
}
