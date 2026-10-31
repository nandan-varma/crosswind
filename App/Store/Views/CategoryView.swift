// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

extension CatalogCategory {
    /// Localized sidebar and header name.
    var title: String {
        switch self {
        case .audio: String(localized: "Audio")
        case .audioVideo: String(localized: "Audio & Video")
        case .development: String(localized: "Development")
        case .education: String(localized: "Education")
        case .game: String(localized: "Games")
        case .graphics: String(localized: "Graphics")
        case .network: String(localized: "Internet")
        case .office: String(localized: "Office")
        case .science: String(localized: "Science")
        case .settings: String(localized: "Settings")
        case .system: String(localized: "System")
        case .utility: String(localized: "Utilities")
        case .video: String(localized: "Video")
        }
    }

    /// SF Symbol shown beside the category in the sidebar.
    var symbol: String {
        switch self {
        case .audio: "music.note"
        case .audioVideo: "play.rectangle.on.rectangle"
        case .development: "hammer"
        case .education: "graduationcap"
        case .game: "gamecontroller"
        case .graphics: "paintpalette"
        case .network: "network"
        case .office: "doc.text"
        case .science: "atom"
        case .settings: "gearshape"
        case .system: "desktopcomputer"
        case .utility: "wrench.and.screwdriver"
        case .video: "film"
        }
    }
}

/// Every app in one category, most popular first.
struct CategoryView: View {
    let category: CatalogCategory
    let model: StoreModel

    var body: some View {
        let apps = model.apps(in: category)
        Group {
            if apps.isEmpty {
                ContentUnavailableView(
                    "No Apps", systemImage: category.symbol,
                    description: Text("No apps are listed in this category yet."))
            } else {
                List {
                    ForEach(apps) { app in
                        AppRow(app: app, model: model)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(category.title)
    }
}

/// Ranked matches for the toolbar search, shown in place of the section content.
struct SearchResultsView: View {
    let query: String
    let model: StoreModel

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = trimmed.isEmpty ? [] : model.search(trimmed)
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView(
                    "Search Apps", systemImage: "magnifyingglass",
                    description: Text("Find apps by name, summary or keyword."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else {
                List {
                    Section {
                        ForEach(results) { app in
                            AppRow(app: app, model: model)
                        }
                    } header: {
                        Text("\(results.count) results")
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Search")
    }
}
