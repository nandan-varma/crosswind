// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The AppStream main categories shown in the store sidebar.
public enum CatalogCategory: String, Sendable, Hashable, CaseIterable {
    case audio = "Audio"
    case audioVideo = "AudioVideo"
    case development = "Development"
    case education = "Education"
    case game = "Game"
    case graphics = "Graphics"
    case network = "Network"
    case office = "Office"
    case science = "Science"
    case settings = "Settings"
    case system = "System"
    case utility = "Utility"
    case video = "Video"
}

public struct CatalogCategoryCount: Sendable, Hashable {
    public let category: CatalogCategory
    public let count: Int
}

/// In-memory search and category index over a catalog snapshot.
public struct CatalogIndex: Sendable {
    /// Ranking tiers, best first. A query matches an app when every token matches at least one field.
    private enum Match: Int, Comparable {
        case description = 1
        case summary = 2
        case wordOrKeyword = 3
        case namePrefix = 4
        case exactName = 5

        static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// An app with its searchable fields folded once, up front.
    private struct Entry: Sendable {
        let app: CatalogApp
        let name: String
        let nameWords: [String]
        let id: String
        let keywords: [String]
        let summary: String
        let description: String
    }

    private let entries: [Entry]
    private let byCategory: [CatalogCategory: [Entry]]

    public init(apps: [CatalogApp]) {
        let entries = apps.map { app in
            let name = Self.fold(app.name)
            return Entry(
                app: app,
                name: name,
                nameWords: name.split { !$0.isLetter && !$0.isNumber }.map(String.init),
                id: Self.fold(app.id),
                keywords: app.keywords.map(Self.fold),
                summary: Self.fold(app.summary),
                description: Self.fold(app.description)
            )
        }
        self.entries = entries
        var byCategory: [CatalogCategory: [Entry]] = [:]
        for entry in entries {
            for category in CatalogCategory.allCases where entry.app.categories.contains(category.rawValue) {
                byCategory[category, default: []].append(entry)
            }
        }
        self.byCategory = byCategory
    }

    /// Apps whose AppStream categories include `category`, ordered by popularity then name.
    public func apps(in category: CatalogCategory, popularity: [String: Double] = [:]) -> [CatalogApp] {
        (byCategory[category] ?? [])
            .sorted { Self.precedes($0, $1, popularity: popularity) }
            .map(\.app)
    }

    /// Every main category with the number of apps listed in it, in `CatalogCategory` order.
    public func categoryCounts() -> [CatalogCategoryCount] {
        CatalogCategory.allCases.map { CatalogCategoryCount(category: $0, count: byCategory[$0]?.count ?? 0) }
    }

    /// Case- and diacritic-insensitive search over name, summary, keywords, ID and description.
    ///
    /// Results rank by the best field match: exact name, name prefix, word or keyword or ID match,
    /// summary, then description. `popularity` (keyed by app ID) breaks ties within a rank; apps
    /// missing from it count as 0. Multi-word queries require every word to match somewhere.
    public func search(_ query: String, popularity: [String: Double] = [:], limit: Int = 50) -> [CatalogApp] {
        let folded = Self.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = folded.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        var ranked: [(entry: Entry, match: Match)] = []
        for entry in entries {
            var weakest: Match?
            if entry.name == folded {
                weakest = .exactName
            } else {
                for token in tokens {
                    guard let match = Self.match(token, in: entry) else {
                        weakest = nil
                        break
                    }
                    weakest = min(weakest ?? .exactName, match)
                }
            }
            if let weakest { ranked.append((entry, weakest)) }
        }

        ranked.sort { lhs, rhs in
            if lhs.match != rhs.match { return lhs.match > rhs.match }
            return Self.precedes(lhs.entry, rhs.entry, popularity: popularity)
        }
        return ranked.prefix(limit).map(\.entry.app)
    }

    private static func match(_ token: String, in entry: Entry) -> Match? {
        if entry.name == token { return .exactName }
        if entry.name.hasPrefix(token) { return .namePrefix }
        let isWordOrKeywordMatch = entry.nameWords.contains { $0.hasPrefix(token) }
            || entry.keywords.contains { $0.hasPrefix(token) }
            || entry.id.contains(token)
        if isWordOrKeywordMatch { return .wordOrKeyword }
        if entry.summary.contains(token) { return .summary }
        if entry.description.contains(token) { return .description }
        return nil
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry, popularity: [String: Double]) -> Bool {
        let lhsScore = popularity[lhs.app.id] ?? 0
        let rhsScore = popularity[rhs.app.id] ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
