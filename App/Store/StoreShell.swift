// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// A sidebar destination in the store.
enum StoreSection: Hashable {
    case discover
    case category(CatalogCategory)
    case installed
    case updates
}

/// Pushes an app's detail page. Carries the ID so the page reads live state from the model.
struct AppRoute: Hashable {
    let id: String
}

/// The store window: sidebar sections, a toolbar search that replaces the detail with ranked results,
/// and app detail pages pushed onto a stack in the detail column.
struct StoreShell: View {
    let model: StoreModel

    @State private var section: StoreSection? = .discover
    @State private var path = NavigationPath()
    @State private var query = ""
    /// The query after the debounce; results follow this rather than every keystroke.
    @State private var activeQuery = ""
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .navigationDestination(for: AppRoute.self) { route in
                        AppDetailView(appID: route.id, model: model)
                    }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Search apps"))
        .searchFocused($searchFocused)
        .task(id: query) { await debounce(query) }
        .onChange(of: section) { _, _ in path = NavigationPath() }
        .onChange(of: isSearching) { _, _ in path = NavigationPath() }
        // Menu commands (Cmd-F, Cmd-1/2/3) reach the window through these scene values.
        .focusedSceneValue(\.storeSection, Binding(get: { section ?? .discover }, set: { section = $0 }))
        .focusedSceneValue(\.storeSearchFocus, Binding(get: { searchFocused }, set: { searchFocused = $0 }))
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section("Store") {
                Label("Discover", systemImage: "sparkles")
                    .tag(StoreSection.discover)
            }
            Section("Categories") {
                ForEach(model.catalog.categoryCounts(), id: \.category) { entry in
                    Label(entry.category.title, systemImage: entry.category.symbol)
                        .badge(entry.count)
                        .tag(StoreSection.category(entry.category))
                }
            }
            Section("Library") {
                Label("Installed", systemImage: "checkmark.circle")
                    .tag(StoreSection.installed)
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .badge(model.updatableApps.count)
                    .accessibilityValue(Text("\(model.updatableApps.count) updates available"))
                    .tag(StoreSection.updates)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
    }

    @ViewBuilder
    private var detail: some View {
        if isSearching {
            SearchResultsView(query: activeQuery, model: model)
        } else {
            switch section ?? .discover {
            case .discover:
                DiscoverView(model: model)
            case .category(let category):
                CategoryView(category: category, model: model)
            case .installed:
                InstalledView(model: model)
            case .updates:
                UpdatesView(model: model)
            }
        }
    }

    private func debounce(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            activeQuery = ""
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        activeQuery = text
    }
}
