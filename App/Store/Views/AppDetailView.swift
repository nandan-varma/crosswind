// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// One app's page: header, screenshots, description, latest release and facts.
struct AppDetailView: View {
    let appID: String
    let model: StoreModel

    @State private var showsFullDescription = false
    @State private var screenshot: ScreenshotSelection?
    @State private var showsCompatibility = false
    @State private var confirmsUninstall = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let app = model.app(appID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header(app)
                    failureBanner(app)
                    screenshots(app)
                    about(app)
                    whatsNew(app)
                    information(app)
                    if model.installed[app.id] != nil {
                        PermissionsView(appID: app.id, store: model)
                            .id(app.id)
                    }
                }
                .padding(28)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(app.name)
            .sheet(item: $screenshot) { selection in
                ScreenshotSheet(screenshot: selection.screenshot)
            }
            .confirmationDialog(
                "Uninstall \(app.name)?", isPresented: $confirmsUninstall, titleVisibility: .visible
            ) {
                Button("Uninstall", role: .destructive) {
                    Task { await model.uninstall(app.id) }
                }
            } message: {
                Text("Your data in this app is kept.")
            }
        } else {
            ContentUnavailableView("App Not Found", systemImage: "questionmark.app")
        }
    }

    // MARK: Header

    private func header(_ app: CatalogApp) -> some View {
        HStack(alignment: .top, spacing: 20) {
            AppIconView(app: app, size: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: app.name)
                    .font(.title.bold())
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: app.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                DeveloperLabel(app: app)
                HStack(spacing: 12) {
                    ActionButton(appID: app.id, model: model)
                        .controlSize(.large)
                        // Return activates the primary action on this page.
                        .keyboardShortcut(.defaultAction)
                    if model.installed[app.id] != nil {
                        if model.isRunning(app.id) {
                            Label("Running", systemImage: "circle.fill")
                                .font(.callout)
                                .foregroundStyle(.green)
                                .accessibilityLabel(Text("Running"))
                        }
                        Menu("More", systemImage: "ellipsis.circle") {
                            Button("Uninstall", systemImage: "trash", role: .destructive) {
                                confirmsUninstall = true
                            }
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(String(localized: "More actions"))
                        .accessibilityLabel(Text("More actions"))
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func failureBanner(_ app: CatalogApp) -> some View {
        if let operation = model.operations[app.id], let failure = operation.failure {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The last action didn't finish")
                        .font(.headline)
                    Text(verbatim: failure)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button("Retry") {
                    Task { await retry(app.id, operation) }
                }
                .buttonStyle(.borderedProminent)
                Button("Dismiss") {
                    model.clearFailure(app.id)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private func retry(_ appID: String, _ operation: AppOperation) async {
        model.clearFailure(appID)
        switch operation.kind {
        case .install:
            if model.installed[appID] != nil {
                await model.open(appID)
            } else {
                await model.install(appID)
            }
        case .update:
            await model.update(appID)
        case .uninstall:
            await model.uninstall(appID)
        }
    }

    // MARK: Screenshots

    @ViewBuilder
    private func screenshots(_ app: CatalogApp) -> some View {
        if !app.screenshots.isEmpty {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(app.screenshots.enumerated()), id: \.offset) { index, shot in
                        Button {
                            screenshot = ScreenshotSelection(id: index, screenshot: shot)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ScreenshotThumbnail(screenshot: shot)
                                if !shot.caption.isEmpty {
                                    Text(verbatim: shot.caption)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(width: 480, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Show a larger view of this screenshot"))
                        .accessibilityLabel(Text("Screenshot \(index + 1) of \(app.screenshots.count)"))
                        .accessibilityHint(Text("Opens a larger view"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: About

    private func about(_ app: CatalogApp) -> some View {
        let paragraphs = app.description
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let collapsedCount = 2
        let visible = showsFullDescription ? paragraphs : Array(paragraphs.prefix(collapsedCount))
        return VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(visible.enumerated()), id: \.offset) { _, paragraph in
                Text(verbatim: paragraph)
                    .textSelection(.enabled)
            }
            if paragraphs.count > collapsedCount {
                Button(showsFullDescription ? "Show Less" : "Show More") {
                    // Reduce Motion: change the text without the animated height change.
                    if reduceMotion {
                        showsFullDescription.toggle()
                    } else {
                        withAnimation(.snappy) { showsFullDescription.toggle() }
                    }
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: What's New

    @ViewBuilder
    private func whatsNew(_ app: CatalogApp) -> some View {
        if let release = app.releases.first {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's New")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text("Version \(release.version)")
                    if let date = release.date {
                        Text(date, style: .date)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let notes = release.description, !notes.isEmpty {
                    Text(verbatim: notes)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

extension AppDetailView {
    // MARK: Information

    fileprivate func information(_ app: CatalogApp) -> some View {
        let installed = model.installed[app.id]
        let categories = app.categories
            .compactMap { CatalogCategory(rawValue: $0)?.title }
            .joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 14) {
                infoRow("License") { Text(verbatim: app.projectLicense ?? String(localized: "Not specified")) }
                infoRow("Developer") { Text(verbatim: app.developerName ?? String(localized: "Unknown")) }
                infoRow("Version") {
                    Text(verbatim: installed?.version ?? app.releases.first?.version ?? String(localized: "Unknown"))
                }
                if let installed {
                    infoRow("Size") {
                        Text(Int64(clamping: installed.installedSize).formatted(.byteCount(style: .file)))
                    }
                }
                if !categories.isEmpty {
                    infoRow("Categories") { Text(categories) }
                }
                infoRow("Compatibility") { compatibility }
                let links = websiteLinks(app)
                if !links.isEmpty {
                    infoRow("Links") {
                        HStack(spacing: 16) {
                            ForEach(links, id: \.url) { link in
                                Link(link.title, destination: link.url)
                                    .help(link.url.absoluteString)
                            }
                        }
                    }
                }
            }
        }
    }

    fileprivate var compatibility: some View {
        let rating = CompatRatings.rating(for: appID)
        let status = rating?.status ?? .untested
        return HStack(spacing: 6) {
            Label(status.title, systemImage: status.symbol)
                .foregroundStyle(status.tint)
                .accessibilityLabel(Text("Compatibility: \(status.title)"))
            Button("About Compatibility", systemImage: "info.circle") {
                showsCompatibility = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help(String(localized: "About Compatibility"))
            .popover(isPresented: $showsCompatibility, arrowEdge: .bottom) {
                Text(verbatim: compatibilityExplanation(rating))
                    .font(.callout)
                    .padding(16)
                    .frame(width: 300, alignment: .leading)
            }
        }
    }

    private func compatibilityExplanation(_ rating: CompatRating?) -> String {
        guard let rating else {
            return String(
                localized: """
                    This app has not been tested on Crosswind yet. Its window, rendering, input and exit were \
                    not checked.
                    """)
        }
        let date = rating.testedAt.formatted(date: .abbreviated, time: .omitted)
        var text = String(
            localized: """
                Tested \(date) on guest image \(rating.guestImageVersion). Each app is launched in the Linux \
                guest and checked for a window, rendered frames, input and a clean exit. The guest renders on \
                the CPU, so GPU-accelerated drawing is not covered.
                """)
        if !rating.note.isEmpty { text += "\n\n" + rating.note }
        return text
    }

    fileprivate func infoRow<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            value()
                .textSelection(.enabled)
        }
    }

    fileprivate struct WebsiteLink: Hashable {
        let title: String
        let url: URL
    }

    fileprivate func websiteLinks(_ app: CatalogApp) -> [WebsiteLink] {
        [
            app.homepage.map { WebsiteLink(title: String(localized: "Website"), url: $0) },
            app.help.map { WebsiteLink(title: String(localized: "Help"), url: $0) },
            app.bugtracker.map { WebsiteLink(title: String(localized: "Report a Problem"), url: $0) },
            app.donation.map { WebsiteLink(title: String(localized: "Donate"), url: $0) },
        ].compactMap { $0 }
    }
}
