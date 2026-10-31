// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum FlathubError: Error, Equatable {
    case badStatus(Int)
    case invalidResponse
}

/// Client for the public Flathub v2 API. Pass a `URLSession` configured with a stub `URLProtocol` in tests.
public struct FlathubAPI: Sendable {
    public enum Collection: String, Sendable {
        /// Ranked by installs in the last month.
        case popular
        /// Ranked by Flathub's trending score.
        case trending
    }

    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://flathub.org/api/v2")!) {
        self.session = session
        self.baseURL = baseURL
    }

    /// One page of a collection. The server returns 250 hits per page at most.
    public func collectionPage(
        _ collection: Collection, page: Int, perPage: Int = 250
    ) async throws -> FlathubCollectionPage {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        return try await get("collection/\(collection.rawValue)", query: query)
    }

    /// Every hit in a collection, keyed by app ID. Popular scores are monthly installs and trending
    /// scores are Flathub's trending value; apps without a value are omitted.
    public func popularityScores(_ collection: Collection) async throws -> [String: Double] {
        let first = try await collectionPage(collection, page: 1)
        var hits = first.hits
        if first.totalPages > 1 {
            hits += try await withThrowingTaskGroup(of: [FlathubHit].self) { group in
                for page in 2...first.totalPages {
                    group.addTask { try await self.collectionPage(collection, page: page).hits }
                }
                return try await group.reduce(into: []) { $0 += $1 }
            }
        }
        var scores: [String: Double] = [:]
        for hit in hits {
            switch collection {
            case .popular: scores[hit.appID] = hit.installsLastMonth.map(Double.init)
            case .trending: scores[hit.appID] = hit.trending
            }
        }
        return scores
    }

    /// Download and installed size, plus the permissions of an app's stable branch.
    public func summary(appID: String) async throws -> FlathubSummary {
        try await get("summary/\(appID)")
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw FlathubError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FlathubError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FlathubError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

public struct FlathubCollectionPage: Decodable, Sendable {
    public let hits: [FlathubHit]
    public let totalPages: Int
}

public struct FlathubHit: Decodable, Sendable, Hashable {
    public let appID: String
    public let installsLastMonth: Int?
    public let trending: Double?
    public let favoritesCount: Int?

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case installsLastMonth = "installs_last_month"
        case trending
        case favoritesCount = "favorites_count"
    }
}

public struct FlathubSummary: Decodable, Sendable, Hashable {
    /// Bytes to download the app's current stable branch.
    public let downloadSize: Int64?
    /// Bytes on disk once installed.
    public let installedSize: Int64?
    public let metadata: FlathubMetadata

    enum CodingKeys: String, CodingKey {
        case downloadSize = "download_size"
        case installedSize = "installed_size"
        case metadata
    }
}

public struct FlathubMetadata: Decodable, Sendable, Hashable {
    public let permissions: FlathubPermissions?
}

/// Flatpak finish-args. Session and system bus policies are not decoded.
public struct FlathubPermissions: Decodable, Sendable, Hashable {
    public let shared: [String]?
    public let sockets: [String]?
    public let devices: [String]?
    public let filesystems: [String]?
}
