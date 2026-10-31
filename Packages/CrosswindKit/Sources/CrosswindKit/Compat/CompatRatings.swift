// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The rating shown in the app's detail view. A generated subset of `results.json`.
public struct CompatRating: Codable, Sendable, Equatable {
    public var status: CompatStatus
    public var note: String
    public var testedAt: Date
    public var guestImageVersion: String

    public init(status: CompatStatus, note: String, testedAt: Date, guestImageVersion: String) {
        self.status = status
        self.note = note
        self.testedAt = testedAt
        self.guestImageVersion = guestImageVersion
    }
}

/// The bundled `CompatRatings.json`: app id to rating.
public struct CompatRatings: Codable, Sendable, Equatable {
    public var apps: [String: CompatRating]

    public init(apps: [String: CompatRating]) {
        self.apps = apps
    }

    public init(records: [CompatRecord]) {
        var apps: [String: CompatRating] = [:]
        for record in records {
            apps[record.appID] = CompatRating(
                status: record.status, note: record.notes.first.map { String($0.prefix(200)) } ?? "",
                testedAt: record.testedAt, guestImageVersion: record.guestImageVersion)
        }
        self.apps = apps
    }

    /// The ratings shipped in the app bundle; empty when the resource is missing.
    public static let bundled: CompatRatings = {
        guard let url = Bundle.main.url(forResource: "CompatRatings", withExtension: "json"),
            let data = try? Data(contentsOf: url), let ratings = try? decode(data)
        else { return CompatRatings(apps: [:]) }
        return ratings
    }()

    /// The rating for an app, or nil when it has not been tested ("Not yet tested").
    public static func rating(for appID: String, in ratings: CompatRatings = bundled) -> CompatRating? {
        ratings.apps[appID]
    }

    public static func decode(_ data: Data) throws -> CompatRatings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CompatRatings.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// Writes `results.json`, `matrix.md` and the bundled ratings from new records merged into the existing results.
public enum CompatReport {
    public static func write(_ records: [CompatRecord], directory: URL, ratingsFile: URL?) throws {
        let resultsURL = directory.appending(path: "results.json")
        let existing = (try? Data(contentsOf: resultsURL)).flatMap { try? CompatResults.decode($0) } ?? []
        let merged = CompatResults.merge(records, into: existing)
        try CompatResults.encode(merged).write(to: resultsURL, options: .atomic)
        try CompatMatrix.markdown(merged).write(
            to: directory.appending(path: "matrix.md"), atomically: true, encoding: .utf8)
        if let ratingsFile {
            try CompatRatings(records: merged).encoded().write(to: ratingsFile, options: .atomic)
        }
    }
}
