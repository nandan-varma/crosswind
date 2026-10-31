// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

/// Serves canned responses for Flathub requests; `handler` is shared, so the suite runs serially.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URL) throws -> (status: Int, body: Data))?

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (status, body) = try handler(url)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            client?.urlProtocol(self, didReceive: response!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

@Suite("Flathub API", .serialized)
struct FlathubAPITests {
    private static func makeAPI() -> FlathubAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return FlathubAPI(session: URLSession(configuration: config))
    }

    @Test("popular scores are monthly installs, keyed by app ID")
    func popularScores() async throws {
        let body = try CatalogFixtures.data("flathub-popular", "json")
        StubURLProtocol.handler = { url in
            #expect(url.path == "/api/v2/collection/popular")
            #expect(url.query?.contains("per_page=250") == true)
            return (200, body)
        }
        let scores = try await Self.makeAPI().popularityScores(.popular)
        #expect(scores["org.darktable.Darktable"] == 244_938)
        #expect(scores.count == 3)
    }

    @Test("trending scores come from the trending field")
    func trendingScores() async throws {
        let body = try CatalogFixtures.data("flathub-trending", "json")
        StubURLProtocol.handler = { _ in (200, body) }
        let scores = try await Self.makeAPI().popularityScores(.trending)
        let kitsune = try #require(scores["net.armatik.Kitsune"])
        #expect(abs(kitsune - 19.998745) < 0.001)
    }

    @Test("pages after the first are fetched and merged")
    func multiplePages() async throws {
        let first = try CatalogFixtures.data("flathub-popular", "json")
        StubURLProtocol.handler = { url in
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "page" }?.value
            if page == "2" {
                let body = #"{"hits":[{"app_id":"org.page.Two","installs_last_month":7}],"totalPages":2}"#
                return (200, Data(body.utf8))
            }
            var object = try #require(JSONSerialization.jsonObject(with: first) as? [String: Any])
            object["totalPages"] = 2
            return (200, try JSONSerialization.data(withJSONObject: object))
        }
        let scores = try await Self.makeAPI().popularityScores(.popular)
        #expect(scores["org.page.Two"] == 7)
        #expect(scores.count == 4)
    }

    @Test("summary decodes sizes and permissions")
    func summary() async throws {
        let body = try CatalogFixtures.data("flathub-summary-darktable", "json")
        StubURLProtocol.handler = { url in
            #expect(url.path == "/api/v2/summary/org.darktable.Darktable")
            return (200, body)
        }
        let summary = try await Self.makeAPI().summary(appID: "org.darktable.Darktable")
        #expect(summary.downloadSize == 72_754_305)
        #expect(summary.installedSize == 183_570_432)
        #expect(summary.metadata.permissions?.shared == ["ipc", "network"])
        #expect(summary.metadata.permissions?.sockets?.contains("wayland") == true)
    }

    @Test("HTTP errors surface as badStatus")
    func httpError() async throws {
        StubURLProtocol.handler = { _ in (404, Data(#"{"detail":"Not Found"}"#.utf8)) }
        await #expect(throws: FlathubError.badStatus(404)) {
            _ = try await Self.makeAPI().summary(appID: "no.such.App")
        }
    }
}
