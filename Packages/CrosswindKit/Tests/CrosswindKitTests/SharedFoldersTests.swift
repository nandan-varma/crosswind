// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString.lowercased())
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func hostPathsMapToGuestPathsInsideGrants() {
    var folders = SharedFolders()
    folders.add(path: "/Volumes/Work/Docs")
    #expect(folders.guestPath(forHostPath: "/Volumes/Work/Docs") == "/mnt/mac/Docs")
    #expect(folders.guestPath(forHostPath: "/Volumes/Work/Docs/a/b.txt") == "/mnt/mac/Docs/a/b.txt")
    #expect(folders.guestPath(forHostPath: "/Volumes/Work/Docs/") == "/mnt/mac/Docs")
}

@Test func pathsOutsideGrantsHaveNoGuestPath() {
    var folders = SharedFolders()
    folders.add(path: "/Volumes/Work/Docs")
    #expect(folders.guestPath(forHostPath: "/Volumes/Work/Docs2/a.txt") == nil)
    #expect(folders.guestPath(forHostPath: "/Volumes/Work") == nil)
    #expect(SharedFolders().guestPath(forHostPath: "/Volumes/Work/Docs/a.txt") == nil)
}

@Test func innermostGrantWinsForNestedFolders() {
    var folders = SharedFolders()
    folders.add(path: "/Volumes/Work")
    folders.add(path: "/Volumes/Work/Docs")
    #expect(folders.guestPath(forHostPath: "/Volumes/Work/Docs/a.txt") == "/mnt/mac/Docs/a.txt")
    #expect(folders.guestPath(forHostPath: "/Volumes/Work/b.txt") == "/mnt/mac/Work/b.txt")
}

@Test func addReusesExistingGrantAndUniquesNames() {
    var folders = SharedFolders()
    let first = folders.add(path: "/Volumes/A/Notes")
    let again = folders.add(path: "/Volumes/A/Notes/")
    let other = folders.add(path: "/Volumes/B/notes")
    #expect(first == again)
    #expect(folders.folders.count == 2)
    #expect(first.name == "Notes")
    #expect(other.name == "notes 2")
}

@Test func reservedStagingNameIsNotUsedForGrants() {
    var folders = SharedFolders()
    let grant = folders.add(path: "/Volumes/A/staging")
    #expect(grant.name == "staging 2")
}

@Test func removeAndReadOnlyUpdateTheGrant() {
    var folders = SharedFolders()
    folders.add(path: "/Volumes/A/Photos")
    folders.setReadOnly(true, name: "Photos")
    #expect(folders.folders.first?.readOnly == true)
    folders.remove(name: "Photos")
    #expect(folders.folders.isEmpty)
}

@Test func grantsRoundTripThroughTheJSONFile() throws {
    let file = try tempDirectory().appending(path: "shared-folders.json")
    var folders = SharedFolders()
    folders.add(path: "/Volumes/A/Photos", readOnly: true)
    try folders.save(to: file)
    #expect(try SharedFolders.load(from: file) == folders)
    let missing = try SharedFolders.load(from: file.deletingLastPathComponent().appending(path: "none.json"))
    #expect(missing.folders.isEmpty)
}

@Test func shareLayoutExportsGrantsAndStaging() throws {
    let staging = try tempDirectory()
    var folders = SharedFolders()
    folders.add(path: "/Volumes/A/Photos", readOnly: true)
    let directories = ShareLayout.directories(for: folders, staging: staging)
    #expect(Set(directories.keys) == ["Photos", "staging"])
    #expect(directories["Photos"]?.isReadOnly == true)
    #expect(directories["staging"]?.isReadOnly == false)
    #expect(directories["staging"]?.url == staging)
}

@Test func filtersFlattenGlobsAndMimeTypes() {
    let filters = FileFilters.parse(["*.PNG", "*.tar.gz", "image/jpeg", "audio/*"])
    #expect(filters.extensions == ["png", "gz"])
    #expect(filters.mimeTypes == ["image/jpeg"])
    #expect(filters.mimeGroups == ["audio"])
    #expect(!filters.allowsAll)
}

@Test func starOrNoFiltersAllowEverything() {
    #expect(FileFilters.parse([]).allowsAll)
    #expect(FileFilters.parse(["*"]).allowsAll)
    #expect(FileFilters.parse(["*/*", "foo*"]).allowsAll)
}

@Test func stagingSyncCopiesOnlyWhenTheFileChanged() {
    let now = Date(timeIntervalSince1970: 1_000)
    let signature = FileSignature(size: 10, modified: now)
    #expect(!StagingSync.needsCopy(staged: nil, copied: nil))
    #expect(StagingSync.needsCopy(staged: signature, copied: nil))
    #expect(!StagingSync.needsCopy(staged: signature, copied: signature))
    #expect(StagingSync.needsCopy(staged: FileSignature(size: 11, modified: now), copied: signature))
    #expect(StagingSync.needsCopy(staged: FileSignature(size: 10, modified: now.addingTimeInterval(1)), copied: signature))
}

@Test func stagingPathsAndCloneUseTheSession() throws {
    let root = try tempDirectory()
    let session = try Staging.makeSession(in: root)
    #expect(Staging.guestPath(session: session, fileName: "a b.txt") == "/mnt/mac/staging/\(session.lastPathComponent)/a b.txt")

    let source = try tempDirectory().appending(path: "source.txt")
    try Data("hello".utf8).write(to: source)
    let clone = try Staging.clone(source, into: session)
    #expect(try Data(contentsOf: clone) == Data("hello".utf8))
    Staging.removeSession(session)
    #expect(!FileManager.default.fileExists(atPath: session.path))
}

@MainActor
@Test func stagedFileSyncCopiesBackOnFlush() throws {
    let session = try Staging.makeSession(in: try tempDirectory())
    let staged = session.appending(path: "out.txt")
    let destination = try tempDirectory().appending(path: "out.txt")
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    FileManager.default.createFile(atPath: staged.path, contents: Data("first".utf8))
    let sync = try StagedFileSync(staged: staged, destination: destination)
    sync.flush()
    #expect(try Data(contentsOf: destination) == Data("first".utf8))
    sync.stop()
    Staging.removeSession(session)
}
