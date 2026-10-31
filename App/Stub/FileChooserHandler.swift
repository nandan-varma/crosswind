// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit
import UniformTypeIdentifiers

/// Answers a guest file chooser call with the native Open or Save panel. The answer is a guest path:
/// - a file inside a granted folder keeps its place, `/mnt/mac/<name>/...`;
/// - an open file outside the grants: the user shares its folder, shares only the file (cloned into staging), or
///   cancels;
/// - a save outside the grants (or into a read-only grant) goes through staging: the chosen destination is created
///   empty, and the guest writes a staged copy that `StagedFileSync` copies back (see `Staging`).
@MainActor
final class FileChooserHandler {
    private var session: URL?
    private var syncs: [StagedFileSync] = []
    /// Tells the agent to re-read the shares. Set by the stub once it is connected.
    var refreshShares: (() async -> Void)?
    /// Set when the current call used the staging directory.
    private var stagedThisCall = false

    private enum OutsideChoice {
        case shareFolder
        case shareFiles
        case cancel
    }

    /// Answers one call. A call that used staging asks the agent to refresh the share before the app gets the path.
    func handle(_ request: Crosswind_Control_FileChooser) async -> Crosswind_Control_CallReply.OneOf_Result {
        stagedThisCall = false
        let result = await answer(request)
        if stagedThisCall { await refreshShares?() }
        return result
    }

    private func answer(_ request: Crosswind_Control_FileChooser) async -> Crosswind_Control_CallReply.OneOf_Result {
        switch request.mode {
        case .save:
            return await save(request)
        case .openDirectory:
            return await open(request, directory: true)
        default:
            return await open(request, directory: false)
        }
    }

    /// Stops the copy-back for every staged file and removes the session. Call when the app exits.
    func finish() {
        for sync in syncs {
            sync.stop()
        }
        syncs.removeAll()
        if let session {
            Staging.removeSession(session)
        }
        session = nil
    }

    // MARK: Open

    private func open(
        _ request: Crosswind_Control_FileChooser, directory: Bool
    ) async -> Crosswind_Control_CallReply.OneOf_Result {
        let panel = NSOpenPanel()
        configure(panel, request)
        panel.canChooseFiles = !directory
        panel.canChooseDirectories = directory
        panel.allowsMultipleSelection = request.multiple
        if !directory, let types = contentTypes(request.filters) {
            panel.allowedContentTypes = types
        }
        guard await present(panel) else { return cancelled }

        var folders = currentFolders()
        var paths: [String] = []
        var outside: [URL] = []
        for url in panel.urls {
            if let guest = folders.guestPath(forHostPath: url.path) {
                paths.append(guest)
            } else {
                outside.append(url)
            }
        }
        // Ask once per folder. A chosen directory is itself the folder to share.
        let groups = Dictionary(grouping: outside) { directory ? $0 : $0.deletingLastPathComponent() }
        for (folder, files) in groups.sorted(by: { $0.key.path < $1.key.path }) {
            switch ask(folder: folder, fileCount: files.count, offerFilesOnly: !directory) {
            case .cancel:
                continue
            case .shareFolder:
                folders.add(path: folder.path)
                guard persist(folders) else { return failed }
                paths += files.compactMap { folders.guestPath(forHostPath: $0.path) }
            case .shareFiles:
                for file in files {
                    guard let staged = try? cloneIntoStaging(file) else { return failed }
                    paths.append(staged)
                }
            }
        }
        return paths.isEmpty ? cancelled : chosen(paths)
    }

    // MARK: Save

    private func save(_ request: Crosswind_Control_FileChooser) async -> Crosswind_Control_CallReply.OneOf_Result {
        let panel = NSSavePanel()
        configure(panel, request)
        panel.nameFieldStringValue = request.suggestedName
        guard await present(panel), let destination = panel.url else { return cancelled }

        // A read-only grant cannot be written by the guest, so it counts as outside.
        let writable = SharedFolders(folders: currentFolders().folders.filter { !$0.readOnly })
        if let guest = writable.guestPath(forHostPath: destination.path) {
            return chosen([guest])
        }
        do {
            // The destination exists at once (empty) so the guest and the user see the same file.
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let session = try currentSession()
            let staged = session.appending(path: destination.lastPathComponent)
            FileManager.default.createFile(atPath: staged.path, contents: nil)
            syncs.append(try StagedFileSync(staged: staged, destination: destination))
            return chosen([Staging.guestPath(session: session, fileName: destination.lastPathComponent)])
        } catch {
            return failed
        }
    }

    // MARK: Helpers

    private func configure(_ panel: NSSavePanel, _ request: Crosswind_Control_FileChooser) {
        if !request.title.isEmpty { panel.message = request.title }
        if !request.acceptLabel.isEmpty { panel.prompt = request.acceptLabel }
    }

    /// Shows the panel as a sheet on the app's window when there is one, else as a modal panel.
    private func present(_ panel: NSSavePanel) async -> Bool {
        if let window = NSApp.keyWindow {
            return await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK)
                }
            }
        }
        return panel.runModal() == .OK
    }

    private func ask(folder: URL, fileCount: Int, offerFilesOnly: Bool) -> OutsideChoice {
        let alert = NSAlert()
        alert.messageText = "Share \(folder.lastPathComponent) with Linux apps?"
        alert.informativeText =
            "Linux apps can read and write everything in shared folders, including subfolders of "
            + "\(folder.path). You can remove the share in Crosswind Settings."
        alert.addButton(withTitle: "Share Folder")
        if offerFilesOnly {
            alert.addButton(withTitle: fileCount == 1 ? "Share Only This File" : "Share Only These Files")
        }
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .shareFolder
        case .alertSecondButtonReturn where offerFilesOnly:
            return .shareFiles
        default:
            return .cancel
        }
    }

    /// The session directory, created on first use.
    private func currentSession() throws -> URL {
        stagedThisCall = true
        if let session { return session }
        let created = try Staging.makeSession()
        session = created
        return created
    }

    private func cloneIntoStaging(_ file: URL) throws -> String {
        let session = try currentSession()
        let clone = try Staging.clone(file, into: session)
        return Staging.guestPath(session: session, fileName: clone.lastPathComponent)
    }

    private func currentFolders() -> SharedFolders {
        (try? SharedFolders.load(from: SharedFolders.defaultFile)) ?? SharedFolders()
    }

    private func persist(_ folders: SharedFolders) -> Bool {
        do {
            try folders.save(to: SharedFolders.defaultFile)
            return true
        } catch {
            return false
        }
    }

    /// Filter strings to content types. Nil (no restriction) when nothing resolves to a type.
    private func contentTypes(_ patterns: [String]) -> [UTType]? {
        let filters = FileFilters.parse(patterns)
        guard !filters.allowsAll else { return nil }
        var types = filters.extensions.compactMap { UTType(filenameExtension: $0) }
        types += filters.mimeTypes.compactMap { UTType(mimeType: $0) }
        for group in filters.mimeGroups {
            switch group {
            case "image": types.append(.image)
            case "audio": types.append(.audio)
            case "video": types.append(.movie)
            case "text": types.append(.plainText)
            default: break
            }
        }
        return types.isEmpty ? nil : types
    }

    private var cancelled: Crosswind_Control_CallReply.OneOf_Result {
        .fileChooser(.with { $0.cancelled = true })
    }

    private var failed: Crosswind_Control_CallReply.OneOf_Result {
        .error(.with { $0.message = "The file chooser failed on the Mac. Check the Crosswind log." })
    }

    private func chosen(_ paths: [String]) -> Crosswind_Control_CallReply.OneOf_Result {
        .fileChooser(.with { $0.paths = paths })
    }
}
