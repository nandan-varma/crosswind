// SPDX-License-Identifier: AGPL-3.0-or-later
import CryptoKit
import Foundation

/// Describes one release of the guest image. The app bundle carries this file; its hashes are what the
/// downloaded files are verified against, so the bundle's code signature protects the image.
public struct GuestImageManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public let name: String
        public let size: Int64
        public let sha256: String
        public let url: URL
    }

    public let version: String
    public let files: [File]

    public init(version: String, files: [File]) {
        self.version = version
        self.files = files
    }
}

public enum ImageStoreError: Error, Equatable {
    case sizeMismatch(String)
    case checksumMismatch(String)
}

/// Downloads, verifies and installs the guest image into `GuestPaths.imageDirectory`.
public actor ImageStore {
    private let paths: GuestPaths
    private let session: URLSession

    public init(paths: GuestPaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    private var versionFile: URL { paths.imageDirectory.appending(path: "VERSION") }

    public func installedVersion() -> String? {
        try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Makes `manifest` the installed image; a no-op when it already is. `progress` reports 0...1 over all files.
    public func install(
        _ manifest: GuestImageManifest, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        if installedVersion() == manifest.version { return }
        let staging = paths.supportDirectory.appending(path: "Image.staging", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let total = Double(manifest.files.reduce(0) { $0 + $1.size })
        var done = 0.0
        for file in manifest.files {
            let base = done
            try await fetch(file, into: staging) { progress((base + $0) / total) }
            done += Double(file.size)
        }
        try manifest.version.write(to: staging.appending(path: "VERSION"), atomically: true, encoding: .utf8)

        try? FileManager.default.removeItem(at: paths.imageDirectory)
        try FileManager.default.moveItem(at: staging, to: paths.imageDirectory)
        progress(1)
    }

    private func fetch(
        _ file: GuestImageManifest.File, into directory: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let observer = ProgressObserver(total: Double(file.size), report: progress)
        let (temporary, _) = try await session.download(from: file.url, delegate: observer)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let size = try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? Int64
        guard size == file.size else { throw ImageStoreError.sizeMismatch(file.name) }
        guard try Self.sha256(of: temporary) == file.sha256 else { throw ImageStoreError.checksumMismatch(file.name) }
        try FileManager.default.moveItem(at: temporary, to: directory.appending(path: file.name))
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Reports a download's byte progress through `URLSessionTask.progress`.
private final class ProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let total: Double
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(total: Double, report: @escaping @Sendable (Double) -> Void) {
        self.total = total
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [total, report] progress, _ in
            report(progress.fractionCompleted * total)
        }
    }
}
