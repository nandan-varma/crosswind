// SPDX-License-Identifier: AGPL-3.0-or-later
import Darwin
import Foundation

/// Files that the user picked outside the granted folders. Each stub session gets a directory under
/// `Application Support/Crosswind/Staging/<uuid>/`. The whole `Staging` directory is always part of the VM share,
/// under the name `staging`, so the guest sees `/mnt/mac/staging/<uuid>/<name>`.
///
/// Sync model (one direction per file):
/// - Open ("Share Only This File"): the file is cloned into the session directory (`clonefile(2)`, instant on APFS).
///   The guest reads the clone. Later edits on the Mac are not seen by the guest, and guest edits never reach the Mac.
/// - Save: the host creates the chosen destination empty and the guest writes into the session copy. The host
///   watches that copy and copies it to the destination after each change, debounced by one second, and once more
///   when the app exits. Atomic save-by-rename is handled by watching the directory, not the file.
/// - Session directories are removed when the app exits.
public enum Staging {
    public static let shareName = "staging"

    /// `Application Support/Crosswind/Staging`.
    public static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Crosswind").appending(path: shareName)
    }

    /// Creates a new session directory under `root` and returns it.
    public static func makeSession(in base: URL = Staging.root) throws -> URL {
        let session = base.appending(path: UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        return session
    }

    /// The guest path of a file in a session directory.
    public static func guestPath(session: URL, fileName: String) -> String {
        "\(SharedFolders.guestMountPoint)/\(shareName)/\(session.lastPathComponent)/\(fileName)"
    }

    /// Clones `source` into `directory` with `clonefile(2)`. Falls back to a plain copy when the volume cannot clone.
    public static func clone(_ source: URL, into directory: URL) throws -> URL {
        let destination = directory.appending(path: source.lastPathComponent)
        if clonefile(source.path, destination.path, 0) == 0 {
            return destination
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Removes a session directory and everything in it.
    public static func removeSession(_ session: URL) {
        try? FileManager.default.removeItem(at: session)
    }
}

/// What the sync compares to decide whether the staged file needs copying: size and modification time.
public struct FileSignature: Equatable, Sendable {
    public var size: UInt64
    public var modified: Date

    public init(size: UInt64, modified: Date) {
        self.size = size
        self.modified = modified
    }

    public init?(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? UInt64,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        self.init(size: size, modified: modified)
    }
}

/// The copy-back decision, kept pure so it can be tested.
public enum StagingSync {
    /// Quiet time after a change before the file is copied back.
    public static let debounce: Duration = .seconds(1)

    /// Copy when the staged file exists and differs from what was last copied (nil: never copied).
    public static func needsCopy(staged: FileSignature?, copied: FileSignature?) -> Bool {
        guard let staged else { return false }
        return staged != copied
    }
}

/// Copies one staged file back to its destination when the guest changes it.
/// Runs on the main actor; the file system events arrive on the main queue.
@MainActor
public final class StagedFileSync {
    public let staged: URL
    public let destination: URL
    private let directoryDescriptor: Int32
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?
    private var copied: FileSignature?

    /// Starts watching the directory that holds `staged`.
    public init(staged: URL, destination: URL) throws {
        self.staged = staged
        self.destination = destination
        let fd = open(staged.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        directoryDescriptor = fd
        let watch = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        watch.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        watch.setCancelHandler { close(fd) }
        watch.resume()
        source = watch
    }

    /// Copies now when the staged file changed since the last copy.
    public func flush() {
        let signature = FileSignature(url: staged)
        guard StagingSync.needsCopy(staged: signature, copied: copied), let signature else { return }
        do {
            let temporary = destination.deletingLastPathComponent()
                .appending(path: ".\(UUID().uuidString.lowercased()).crosswind-part")
            try FileManager.default.copyItem(at: staged, to: temporary)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            copied = signature
        } catch {
            Log.vm.error("copy-back to \(self.destination.lastPathComponent, privacy: .public) failed: \(error)")
        }
    }

    /// Final copy and stop watching. Call when the app exits, before the session directory is removed.
    public func stop() {
        pending?.cancel()
        flush()
        source?.cancel()
        source = nil
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: StagingSync.debounce)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
