// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One folder the user granted to Linux apps. Each grant is one directory in the guest, under `/mnt/mac/<name>`.
public struct SharedFolder: Codable, Equatable, Sendable {
    /// Directory name in the guest, unique within the grants.
    public var name: String
    /// Absolute host path, normalized (symlinks resolved).
    public var path: String
    public var readOnly: Bool

    public init(name: String, path: String, readOnly: Bool) {
        self.name = name
        self.path = path
        self.readOnly = readOnly
    }
}

/// The user's folder grants. No folder is shared by default. Persisted as JSON in
/// `Application Support/Crosswind/shared-folders.json`.
///
/// Linux apps can read and write everything in a shared folder, so a grant is the user's explicit decision.
public struct SharedFolders: Codable, Equatable, Sendable {
    /// Where the host's virtiofs share `mac` appears in the guest.
    public static let guestMountPoint = "/mnt/mac"
    /// The virtiofs tag of the host share; the guest mounts it with `mount -t virtiofs mac /mnt/mac`.
    public static let mountTag = "mac"
    /// `Application Support/Crosswind/shared-folders.json`.
    public static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Crosswind").appending(path: "shared-folders.json")
    }
    /// Name of the staging directory (see `Staging`). Grants may not use it.
    public static let reservedNames: Set<String> = [Staging.shareName]

    public private(set) var folders: [SharedFolder]

    public init(folders: [SharedFolder] = []) {
        self.folders = folders
    }

    /// Loads the grants. A missing file means no grants.
    public static func load(from url: URL) throws -> SharedFolders {
        guard FileManager.default.fileExists(atPath: url.path) else { return SharedFolders() }
        return try JSONDecoder().decode(SharedFolders.self, from: Data(contentsOf: url))
    }

    /// Writes the grants atomically.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Grants `path` (a folder or a file's parent). Returns the existing grant when the folder is already shared.
    @discardableResult
    public mutating func add(path: String, readOnly: Bool = false) -> SharedFolder {
        let normalized = Self.normalize(path)
        if let existing = folders.first(where: { $0.path == normalized }) {
            return existing
        }
        let taken = Set(folders.map { $0.name.lowercased() })
        let base = (normalized as NSString).lastPathComponent
        let folder = SharedFolder(
            name: Self.uniqueName(base: base.isEmpty ? "Folder" : base, taken: taken),
            path: normalized,
            readOnly: readOnly)
        folders.append(folder)
        return folder
    }

    public mutating func remove(name: String) {
        folders.removeAll { $0.name == name }
    }

    public mutating func setReadOnly(_ readOnly: Bool, name: String) {
        guard let index = folders.firstIndex(where: { $0.name == name }) else { return }
        folders[index].readOnly = readOnly
    }

    /// The guest path of a host path inside a grant, e.g. `/mnt/mac/Documents/a/b.txt`. Nil when no grant
    /// contains it. With nested grants the innermost one wins.
    public func guestPath(forHostPath hostPath: String) -> String? {
        let target = Self.normalize(hostPath)
        let containing = folders.filter { folder in
            let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
            return target == folder.path || target.hasPrefix(prefix)
        }
        guard let folder = containing.max(by: { $0.path.count < $1.path.count }) else { return nil }
        let relative = target.dropFirst(folder.path.count).drop { $0 == "/" }
        let mount = "\(Self.guestMountPoint)/\(folder.name)"
        return relative.isEmpty ? mount : "\(mount)/\(relative)"
    }

    /// Resolves symlinks and removes `.`/`..` and trailing slashes, so grant paths compare reliably.
    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// `base`, or `base 2`, `base 3`, ... so that the name is not taken (case-insensitively, as macOS
    /// file names are) and is not reserved.
    public static func uniqueName(base: String, taken: Set<String>) -> String {
        func free(_ name: String) -> Bool {
            !taken.contains(name.lowercased()) && !reservedNames.contains(name.lowercased())
        }
        if free(base) { return base }
        var index = 2
        while !free("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}
