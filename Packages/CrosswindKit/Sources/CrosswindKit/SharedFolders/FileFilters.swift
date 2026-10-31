// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The file types an app asked for, from the portal's filter strings (`*.png`, `image/png`, `image/*`, `*`).
/// Approximations are deliberate: `*.tar.gz` becomes `gz`, which allows a superset, so no file the app wants is hidden.
public struct FileFilters: Equatable, Sendable {
    /// Lowercased extensions without the dot.
    public var extensions: [String] = []
    /// Full MIME types, e.g. `image/png`.
    public var mimeTypes: [String] = []
    /// Top-level MIME groups from `type/*`, e.g. `image`.
    public var mimeGroups: [String] = []
    /// True when no pattern restricts the choice (no filters, or `*`).
    public var allowsAll: Bool { extensions.isEmpty && mimeTypes.isEmpty && mimeGroups.isEmpty }

    public init() {}

    public static func parse(_ patterns: [String]) -> FileFilters {
        var filters = FileFilters()
        for raw in patterns {
            let pattern = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if pattern == "*" || pattern == "*/*" || pattern.isEmpty {
                continue
            } else if pattern.contains("/") {
                if pattern.hasSuffix("/*") {
                    filters.mimeGroups.append(String(pattern.dropLast(2)))
                } else if !pattern.contains("*") {
                    filters.mimeTypes.append(pattern)
                }
            } else if pattern.hasPrefix("*."), let dot = pattern.lastIndex(of: ".") {
                let ext = String(pattern[pattern.index(after: dot)...])
                if !ext.isEmpty, !ext.contains("*"), !ext.contains("?") {
                    filters.extensions.append(ext)
                }
            }
        }
        return filters
    }
}
