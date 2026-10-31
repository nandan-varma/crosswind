// SPDX-License-Identifier: AGPL-3.0-or-later
import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import CrosswindKit

/// A manifest whose files are served from a temporary directory through `file://` URLs.
private struct ImageFixture {
    let root: URL
    let source: URL
    let paths: GuestPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "ImageStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        source = root.appending(path: "source", directoryHint: .isDirectory)
        paths = GuestPaths(supportDirectory: root.appending(path: "support", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// Writes `name` with `bytes` into the source directory and describes it as a manifest entry.
    func file(
        _ name: String, _ bytes: String, size: Int64? = nil, sha256: String? = nil
    ) throws -> GuestImageManifest.File {
        let url = source.appending(path: name)
        try Data(bytes.utf8).write(to: url)
        return GuestImageManifest.File(
            name: name,
            size: size ?? Int64(bytes.utf8.count),
            sha256: sha256 ?? Self.hex(SHA256.hash(data: Data(bytes.utf8))),
            url: url)
    }

    var imageDirectory: URL { paths.imageDirectory }
    var stagingDirectory: URL { paths.supportDirectory.appending(path: "Image.staging", directoryHint: .isDirectory) }

    func installedContents(_ name: String) throws -> String {
        try String(contentsOf: imageDirectory.appending(path: name), encoding: .utf8)
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

@Suite("ImageStore")
struct ImageStoreTests {
    @Test("installs every file and writes VERSION when nothing is installed")
    func installsWhenEmpty() async throws {
        let fixture = try ImageFixture()
        defer { fixture.remove() }
        let kernel = try fixture.file("kernel.bin", "kernel-bytes")
        let root = try fixture.file("root.img", "root-image-bytes")
        let initrd = try fixture.file("initrd.gz", "initrd")
        let manifest = GuestImageManifest(version: "2.0", files: [kernel, root, initrd])
        let store = ImageStore(paths: fixture.paths)
        let reports = Mutex<[Double]>([])

        try await store.install(manifest) { fraction in reports.withLock { $0.append(fraction) } }

        #expect(await store.installedVersion() == "2.0")
        #expect(try fixture.installedContents("kernel.bin") == "kernel-bytes")
        #expect(try fixture.installedContents("root.img") == "root-image-bytes")
        #expect(try fixture.installedContents("initrd.gz") == "initrd")
        #expect(try fixture.installedContents("VERSION") == "2.0")
        #expect(!FileManager.default.fileExists(atPath: fixture.stagingDirectory.path))

        let values = reports.withLock { $0 }
        #expect(values.last == 1)
        #expect(values.allSatisfy { (0...1).contains($0) })
    }

    @Test("skips the download when the installed version already matches")
    func skipsWhenVersionMatches() async throws {
        let fixture = try ImageFixture()
        defer { fixture.remove() }
        let store = ImageStore(paths: fixture.paths)
        try await store.install(GuestImageManifest(version: "1.0", files: [try fixture.file("a.bin", "aaa")]))

        // The second manifest points at a file that does not exist; a real download would throw.
        let missing = GuestImageManifest.File(
            name: "a.bin", size: 3, sha256: "unused", url: fixture.source.appending(path: "missing.bin"))
        try await store.install(GuestImageManifest(version: "1.0", files: [missing]))

        #expect(await store.installedVersion() == "1.0")
        #expect(try fixture.installedContents("a.bin") == "aaa")
    }

    @Test("rejects a size mismatch and leaves the previous image untouched")
    func rejectsSizeMismatch() async throws {
        let fixture = try ImageFixture()
        defer { fixture.remove() }
        let store = ImageStore(paths: fixture.paths)
        try await store.install(GuestImageManifest(version: "1", files: [try fixture.file("a.bin", "old")]))

        let bad = GuestImageManifest(
            version: "2", files: [try fixture.file("a.bin", "new-content", size: 999)])
        await #expect(throws: ImageStoreError.sizeMismatch("a.bin")) { try await store.install(bad) }

        #expect(await store.installedVersion() == "1")
        #expect(try fixture.installedContents("a.bin") == "old")
    }

    @Test("rejects a wrong sha256 and leaves the previous image untouched")
    func rejectsChecksumMismatch() async throws {
        let fixture = try ImageFixture()
        defer { fixture.remove() }
        let store = ImageStore(paths: fixture.paths)
        try await store.install(GuestImageManifest(version: "1", files: [try fixture.file("a.bin", "old")]))

        let wrongHash = String(repeating: "0", count: 64)
        let bad = GuestImageManifest(
            version: "2", files: [try fixture.file("a.bin", "new-content", sha256: wrongHash)])
        await #expect(throws: ImageStoreError.checksumMismatch("a.bin")) { try await store.install(bad) }

        #expect(await store.installedVersion() == "1")
        #expect(try fixture.installedContents("a.bin") == "old")
    }

    @Test("recovers on the next install after a failed attempt")
    func recoversAfterFailure() async throws {
        let fixture = try ImageFixture()
        defer { fixture.remove() }
        let store = ImageStore(paths: fixture.paths)
        let bad = GuestImageManifest(
            version: "2", files: [try fixture.file("a.bin", "content", sha256: String(repeating: "0", count: 64))])
        await #expect(throws: ImageStoreError.self) { try await store.install(bad) }
        #expect(await store.installedVersion() == nil)

        let good = GuestImageManifest(version: "2", files: [try fixture.file("a.bin", "content")])
        try await store.install(good)

        #expect(await store.installedVersion() == "2")
        #expect(try fixture.installedContents("a.bin") == "content")
        #expect(!FileManager.default.fileExists(atPath: fixture.stagingDirectory.path))
    }

    @Test("replaces an older version wholesale")
    func replacesOlderVersion() async throws {
        let fixture = try ImageFixture()
        defer { fixture.remove() }
        let store = ImageStore(paths: fixture.paths)
        try await store.install(
            GuestImageManifest(
                version: "1",
                files: [try fixture.file("a.bin", "a1"), try fixture.file("b.bin", "b1")]))

        try await store.install(
            GuestImageManifest(
                version: "2",
                files: [try fixture.file("a.bin", "a2"), try fixture.file("c.bin", "c2")]))

        #expect(await store.installedVersion() == "2")
        #expect(try fixture.installedContents("a.bin") == "a2")
        #expect(try fixture.installedContents("c.bin") == "c2")
        #expect(!FileManager.default.fileExists(atPath: fixture.imageDirectory.appending(path: "b.bin").path))
    }
}
