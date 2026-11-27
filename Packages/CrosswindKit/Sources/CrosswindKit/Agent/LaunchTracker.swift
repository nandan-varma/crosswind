// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Which launches of which apps are alive. One app can have several: opening a file in a running app starts a second
/// `flatpak run` that hands the file to the first and exits at once, and that exit must not count as the app quitting.
public struct LaunchTracker: Equatable, Sendable {
    private var launches: [String: Set<String>] = [:]

    public init() {}

    /// Apps with at least one live launch, sorted.
    public var runningApps: [String] { launches.keys.sorted() }

    public func isRunning(_ appID: String) -> Bool { launches[appID] != nil }

    public mutating func started(appID: String, launchID: String) {
        launches[appID, default: []].insert(launchID)
    }

    /// Records an exit. Returns true when it was the app's last live launch, that is, the app has quit.
    @discardableResult
    public mutating func exited(appID: String, launchID: String) -> Bool {
        guard var live = launches[appID] else { return false }
        live.remove(launchID)
        launches[appID] = live.isEmpty ? nil : live
        return live.isEmpty
    }

    public mutating func removeAll() { launches.removeAll() }
}
