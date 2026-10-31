// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Compatibility matrix and ratings")
struct CompatMatrixTests {
    private static let when = Date(timeIntervalSince1970: 1_780_000_000)

    private static func record(_ id: String, _ name: String, _ status: CompatStatus, note: String = "") -> CompatRecord {
        CompatRecord(
            appID: id, name: name, status: status, notes: note.isEmpty ? [] : [note], testedAt: when,
            guestImageVersion: "0.4.0", arch: "aarch64")
    }

    @Test("matrix sorts by status, then name, and counts each status")
    func sorting() {
        let markdown = CompatMatrix.markdown([
            Self.record("org.z.Z", "Zed", .works),
            Self.record("org.b.B", "beta", .broken, note: "no window"),
            Self.record("org.a.A", "Alpha", .works),
        ])
        let alpha = try! #require(markdown.range(of: "`org.a.A`"))
        let zed = try! #require(markdown.range(of: "`org.z.Z`"))
        let beta = try! #require(markdown.range(of: "`org.b.B`"))
        #expect(alpha.lowerBound < zed.lowerBound)
        #expect(zed.lowerBound < beta.lowerBound)
        #expect(markdown.contains("- Works: 2"))
        #expect(markdown.contains("- Known issues: 1"))
        #expect(markdown.contains("GPU"))
    }

    @Test("notes are escaped for table cells")
    func escaping() {
        let markdown = CompatMatrix.markdown([Self.record("org.a.A", "A", .broken, note: "a|b\nc")])
        #expect(markdown.contains("a\\|b c"))
    }

    @Test("ratings look up by app id and a missing app is not yet tested")
    func lookup() throws {
        let ratings = CompatRatings(records: [Self.record("org.a.A", "A", .caveats, note: "input unknown")])
        let rating = try #require(CompatRatings.rating(for: "org.a.A", in: ratings))
        #expect(rating.status == .caveats)
        #expect(rating.note == "input unknown")
        #expect(CompatRatings.rating(for: "org.none.None", in: ratings) == nil)
    }

    @Test("ratings file survives encode and decode")
    func ratingsRoundTrip() throws {
        let ratings = CompatRatings(records: [Self.record("org.a.A", "A", .works)])
        #expect(try CompatRatings.decode(try ratings.encoded()) == ratings)
    }

    @Test("report writes results, matrix and ratings and merges with earlier runs")
    func report() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "compat-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ratingsURL = directory.appending(path: "CompatRatings.json")

        try CompatReport.write([Self.record("org.a.A", "A", .broken)], directory: directory, ratingsFile: ratingsURL)
        try CompatReport.write([Self.record("org.b.B", "B", .works)], directory: directory, ratingsFile: ratingsURL)

        let results = try CompatResults.decode(Data(contentsOf: directory.appending(path: "results.json")))
        #expect(results.map(\.appID) == ["org.a.A", "org.b.B"])
        let ratings = try CompatRatings.decode(Data(contentsOf: ratingsURL))
        #expect(ratings.apps["org.a.A"]?.status == .broken)
        #expect(ratings.apps["org.b.B"]?.status == .works)
        let matrix = try String(contentsOf: directory.appending(path: "matrix.md"), encoding: .utf8)
        #expect(matrix.contains("# Compatibility matrix"))
    }
}
