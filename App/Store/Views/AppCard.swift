// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

extension CatalogApp {
    /// Stand-in content for skeleton rows; never shown with a real ID.
    static func placeholder(_ index: Int) -> CatalogApp {
        var app = CatalogApp()
        app.id = "placeholder-\(index)"
        app.name = "Application Name"
        app.summary = "A short description of what the application does."
        return app
    }
}

/// Developer name with Flathub's verified-publisher seal.
struct DeveloperLabel: View {
    let app: CatalogApp

    var body: some View {
        if let developer = app.developerName, !developer.isEmpty {
            HStack(spacing: 4) {
                Text(verbatim: developer)
                if app.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Verified developer"))
                        .help(String(localized: "Verified developer"))
                }
            }
            // One element, so VoiceOver reads "<developer>, Verified developer".
            .accessibilityElement(children: .combine)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// A grid or carousel tile: icon, name, two-line summary and the primary action.
struct AppCard: View {
    let app: CatalogApp
    let model: StoreModel
    var showsAction = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: AppRoute(id: app.id)) {
                VStack(alignment: .leading, spacing: 10) {
                    AppIconView(app: app, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: app.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(verbatim: app.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // The card's link reads as one element: name, then summary.
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            if showsAction {
                ActionButton(appID: app.id, model: model)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A list row: icon, name, summary, developer and the primary action.
struct AppRow: View {
    let app: CatalogApp
    let model: StoreModel

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AppRoute(id: app.id)) {
                HStack(spacing: 12) {
                    AppIconView(app: app, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: app.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(verbatim: app.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        DeveloperLabel(app: app)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            ActionButton(appID: app.id, model: model)
        }
        .padding(.vertical, 6)
    }
}
