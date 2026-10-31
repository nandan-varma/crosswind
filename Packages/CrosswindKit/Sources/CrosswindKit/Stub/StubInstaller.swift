// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum StubError: Error {
    case invalidTemplate
    case signingFailed(String)
}

/// Generates and removes the per-app stub bundles that give each Linux app its own Dock tile, Cmd-Tab entry and
/// Launchpad/Spotlight presence. A stub is a copy of the template app with its own identity, signed ad hoc on this Mac.
public struct StubInstaller: Sendable {
    public static let idKey = "CrosswindAppID"

    private let template: URL
    private let directory: URL

    /// `directory` defaults to ~/Applications/Crosswind, which Spotlight and Launchpad index.
    public init(template: URL, directory: URL = Self.defaultDirectory) {
        self.template = template
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        URL.homeDirectory.appending(path: "Applications/Crosswind", directoryHint: .isDirectory)
    }

    /// Creates or refreshes the stub for `appID` and returns its bundle URL. `iconPNG` is any image; it is
    /// converted to an .icns before the template is copied, so a bad image fails without leaving a stub behind.
    @discardableResult
    public func install(appID: String, name: String, version: String, iconPNG: Data? = nil) throws -> URL {
        let fileManager = FileManager.default
        let icns = try iconPNG.map(makeICNS)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = existingStub(for: appID) ?? directory.appending(path: "\(uniqueName(name, appID: appID)).app")
        try? fileManager.removeItem(at: bundle)
        try fileManager.copyItem(at: template, to: bundle)

        let plistURL = bundle.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
            var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw StubError.invalidTemplate }
        plist["CFBundleName"] = name
        plist["CFBundleDisplayName"] = name
        plist["CFBundleIdentifier"] = "dev.crosswind.app." + appID.lowercased()
        plist["CFBundleShortVersionString"] = version
        plist[Self.idKey] = appID
        if let icns {
            let resources = bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
            try icns.write(to: resources.appending(path: "AppIcon.icns"))
            plist["CFBundleIconFile"] = "AppIcon"
        }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)

        try sign(bundle)
        return bundle
    }

    public func remove(appID: String) throws {
        if let bundle = existingStub(for: appID) { try FileManager.default.removeItem(at: bundle) }
    }

    /// App ids of the installed stubs.
    public func installedAppIDs() -> [String] {
        stubs().map(\.appID)
    }

    public func bundleURL(for appID: String) -> URL? { existingStub(for: appID) }

    // MARK: Private

    private func stubs() -> [(appID: String, url: URL)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "app" }.compactMap { url in
            let plist = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist"))
            return (plist?[Self.idKey] as? String).map { ($0, url) }
        }
    }

    private func existingStub(for appID: String) -> URL? {
        stubs().first { $0.appID == appID }?.url
    }

    /// Two apps may share a display name; the second gets its id appended.
    private func uniqueName(_ name: String, appID: String) -> String {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let taken = FileManager.default.fileExists(atPath: directory.appending(path: "\(safe).app").path)
        return taken ? "\(safe) (\(appID))" : safe
    }

    /// Renders the PNG to an .iconset and compiles it to .icns. The scratch directory is always removed.
    private func makeICNS(from png: Data) throws -> Data {
        let iconSet = try IconRenderer.iconSet(from: png)
        let scratch = iconSet.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let icns = scratch.appending(path: "AppIcon.icns")
        try run("/usr/bin/iconutil", ["-c", "icns", "-o", icns.path, iconSet.path])
        return try Data(contentsOf: icns)
    }

    private func sign(_ bundle: URL) throws {
        try run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw StubError.signingFailed("\(tool): \(text)")
        }
    }
}
