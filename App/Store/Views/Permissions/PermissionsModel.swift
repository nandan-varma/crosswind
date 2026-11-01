// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import Observation

/// Edits one installed app's permissions. Edits are saved after a short pause. "Reset to Defaults" clears the
/// override and can be undone until the next edit.
@MainActor
@Observable
final class PermissionsModel {
    enum Load: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let appID: String
    private(set) var load = Load.loading
    /// The manifest defaults, when the guest can tell them apart from the user's overrides.
    private(set) var defaults: AppPermissions?
    private(set) var draft = AppPermissions()
    /// Set by a reset, so the reset can be undone.
    private(set) var beforeReset: AppPermissions?
    private(set) var failure: String?

    private let store: StoreModel
    private var saveTask: Task<Void, Never>?
    private static let pause = Duration.milliseconds(600)

    init(appID: String, store: StoreModel) {
        self.appID = appID
        self.store = store
    }

    /// What edits are compared against: the defaults, or the current values when the guest reports none.
    var baseline: AppPermissions { defaults ?? draft }

    var changeCount: Int { draft.changeCount(from: baseline) }

    var canReset: Bool { defaults != nil && (changeCount > 0 || beforeReset != nil) }

    func fetch() async {
        do {
            let report = try await store.permissions(for: appID)
            draft = report.effective
            defaults = report.defaults
            load = .loaded
        } catch {
            load = .failed(error.localizedDescription)
        }
    }

    /// Applies one edit and saves it after a short pause, so that a run of toggles is one request.
    func edit(_ change: (inout AppPermissions) -> Void) {
        var next = draft
        change(&next)
        guard next != draft else { return }
        draft = next
        beforeReset = nil
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    /// Clears the override: the app gets its manifest permissions again.
    func resetToDefaults() {
        guard let defaults else { return }
        beforeReset = draft
        draft = defaults
        saveNow()
    }

    func undoReset() {
        guard let beforeReset else { return }
        draft = beforeReset
        self.beforeReset = nil
        saveNow()
    }

    /// Stops the running app and opens it again, so that the saved permissions apply.
    func restart() async {
        do {
            try await store.restartApp(appID)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = Task { await save() }
    }

    private func save() async {
        do {
            try await store.setPermissions(for: appID, draft)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
