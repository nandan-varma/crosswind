// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

extension FocusedValues {
    /// The store window's sidebar selection, set by `StoreShell`.
    @Entry var storeSection: Binding<StoreSection>?
    /// The store window's toolbar search focus, set by `StoreShell`.
    @Entry var storeSearchFocus: Binding<Bool>?
}

/// Window menu and keyboard shortcuts for the store: Cmd-F focuses search, Cmd-1/2/3 switch sections.
struct StoreCommands: Commands {
    @FocusedValue(\.storeSection) private var section
    @FocusedValue(\.storeSearchFocus) private var searchFocus

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find Apps") { searchFocus?.wrappedValue = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchFocus == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Discover") { section?.wrappedValue = .discover }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(section == nil)
            Button("Installed") { section?.wrappedValue = .installed }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(section == nil)
            Button("Updates") { section?.wrappedValue = .updates }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(section == nil)
        }
    }
}

/// The Help menu: the documentation, the issue tracker and the release notes, all on the website or GitHub.
struct HelpCommands: Commands {
    private static let site = URL(string: "https://crosswind.nandan.fyi")!
    private static let repository = URL(string: "https://github.com/nandan-varma/crosswind")!

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Crosswind Help", destination: Self.site.appending(path: "docs/getting-started/"))
            Link("What Works: App Compatibility", destination: Self.site.appending(path: "docs/compatibility/"))
            Divider()
            Link("Release Notes", destination: Self.repository.appending(path: "blob/main/CHANGELOG.md"))
            Link("Report an Issue…", destination: Self.repository.appending(path: "issues/new"))
            Link("Crosswind on GitHub", destination: Self.repository)
        }
    }
}
