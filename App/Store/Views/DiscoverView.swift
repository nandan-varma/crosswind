// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// The front page: a trending hero carousel, popular apps, a browse grid and the top apps in three categories.
/// Popularity loads after the catalog; until it arrives the page shows a skeleton, and if it never arrives
/// it falls back to catalog order instead of spinning forever.
struct DiscoverView: View {
    let model: StoreModel

    @State private var popularityTimedOut = false

    private var isLoadingPopularity: Bool {
        model.popularity.isEmpty && model.trending.isEmpty && !popularityTimedOut
    }

    private var popularApps: [CatalogApp] {
        if isLoadingPopularity { return [] }
        let ranked = model.popular(limit: 40)
        return ranked.isEmpty ? fallbackApps : ranked
    }

    private var heroApps: [CatalogApp] {
        let trending = model.trendingApps(limit: 5)
        return trending.isEmpty ? Array(popularApps.prefix(5)) : trending
    }

    /// Every category's apps, de-duplicated and sorted by name, used when there is no popularity data.
    private var fallbackApps: [CatalogApp] {
        var seen = Set<String>()
        return CatalogCategory.allCases
            .flatMap { model.apps(in: $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(40)
            .map { $0 }
    }

    private var topCategories: [CatalogCategory] {
        model.catalog.categoryCounts()
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map(\.category)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                if isLoadingPopularity {
                    skeleton
                } else {
                    if !heroApps.isEmpty {
                        hero(heroApps)
                    }
                    if !popularApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(Text("Popular"))
                            appRow(Array(popularApps.prefix(12)))
                        }
                        if popularApps.count > 12 {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader(Text("Browse"))
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)],
                                    alignment: .leading, spacing: 16
                                ) {
                                    ForEach(popularApps.dropFirst(12)) { app in
                                        AppCard(app: app, model: model)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(topCategories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(Text(String(localized: "Top in \(category.title)")))
                            appRow(Array(model.apps(in: category).prefix(12)))
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Discover")
        .task(id: model.phase == .ready) {
            guard model.phase == .ready else { return }
            try? await Task.sleep(for: .seconds(6))
            popularityTimedOut = true
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 36) {
            HeroCard(app: .placeholder(0), model: model)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(Text("Popular"))
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(0..<6, id: \.self) { index in
                            AppCard(app: .placeholder(index), model: model, showsAction: false)
                                .frame(width: 280)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
            }
        }
    }

    private func hero(_ apps: [CatalogApp]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(apps) { app in
                    HeroCard(app: app, model: model)
                        .containerRelativeFrame(.horizontal) { length, _ in length * 0.92 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func appRow(_ apps: [CatalogApp]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(apps) { app in
                    AppCard(app: app, model: model)
                        .frame(width: 280)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }
}

/// A large trending app with a subtle material background.
private struct HeroCard: View {
    let app: CatalogApp
    let model: StoreModel

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            NavigationLink(value: AppRoute(id: app.id)) {
                HStack(alignment: .center, spacing: 24) {
                    AppIconView(app: app, size: 128)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trending")
                            .font(.caption.bold())
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Text(app.name)
                            .font(.largeTitle.bold())
                            .lineLimit(2)
                        Text(app.summary)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ActionButton(appID: app.id, model: model)
                .controlSize(.large)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
