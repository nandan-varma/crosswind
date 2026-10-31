// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// User settings shared by the store app and every app stub (a common defaults domain, not each bundle's own).
public enum Preferences {
    nonisolated(unsafe) public static let suite = UserDefaults(suiteName: "dev.crosswind.shared") ?? .standard

    public enum Key {
        /// Command acts as Control in Linux apps (Cmd+C copies). Default on.
        public static let commandActsAsControl = "commandActsAsControl"
    }

    public static var commandActsAsControl: Bool {
        suite.object(forKey: Key.commandActsAsControl) as? Bool ?? true
    }
}
