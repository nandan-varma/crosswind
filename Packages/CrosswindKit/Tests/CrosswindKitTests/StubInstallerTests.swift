// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CrosswindKit

@Suite final class StubInstallerTests {
    private let root: URL
    private let template: URL
    private let directory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        template = root.appending(path: "Template.app", directoryHint: .isDirectory)
        directory = root.appending(path: "Installed", directoryHint: .isDirectory)
        let macOS = template.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appending(path: "stub"))
        let plist: [String: Any] = [
            "CFBundleExecutable": "stub",
            "CFBundleName": "Template",
            "CFBundleIdentifier": "dev.crosswind.template",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: template.appending(path: "Contents/Info.plist"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func installer() -> StubInstaller {
        StubInstaller(template: template, directory: directory)
    }

    private func plist(of bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appending(path: "Contents/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// Solid 64x64 blue square, opaque.
    private func iconPNG() throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func installRewritesIdentityAndSigns() throws {
        let bundle = try installer().install(appID: "org.gnome.Calculator", name: "Calculator", version: "46.1")
        #expect(bundle == directory.appending(path: "Calculator.app"))
        let info = try plist(of: bundle)
        #expect(info["CFBundleName"] as? String == "Calculator")
        #expect(info["CFBundleDisplayName"] as? String == "Calculator")
        #expect(info["CFBundleIdentifier"] as? String == "dev.crosswind.app.org.gnome.calculator")
        #expect(info["CFBundleShortVersionString"] as? String == "46.1")
        #expect(info[StubInstaller.idKey] as? String == "org.gnome.Calculator")
        #expect(info["CFBundleIconFile"] == nil)
        #expect(!FileManager.default.fileExists(atPath: bundle.appending(path: "Contents/Resources/AppIcon.icns").path))
    }

    @Test func iconPNGProducesAppIcon() throws {
        let bundle = try installer().install(
            appID: "org.example.Icon", name: "Icon", version: "1", iconPNG: try iconPNG())
        let icns = bundle.appending(path: "Contents/Resources/AppIcon.icns")
        #expect(FileManager.default.fileExists(atPath: icns.path))
        #expect(try Data(contentsOf: icns).count > 0)
        #expect(try plist(of: bundle)["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test func lookupsReflectInstalledStubs() throws {
        let stubs = installer()
        #expect(stubs.installedAppIDs().isEmpty)
        #expect(stubs.bundleURL(for: "org.example.A") == nil)

        try stubs.install(appID: "org.example.A", name: "Alpha", version: "1")
        try stubs.install(appID: "org.example.B", name: "Beta", version: "1")
        #expect(Set(stubs.installedAppIDs()) == ["org.example.A", "org.example.B"])
        #expect(stubs.bundleURL(for: "org.example.A")?.lastPathComponent == "Alpha.app")

        try stubs.remove(appID: "org.example.A")
        #expect(stubs.bundleURL(for: "org.example.A") == nil)
        #expect(stubs.installedAppIDs() == ["org.example.B"])
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "Alpha.app").path))
    }

    @Test func nameCollisionGetsAppIDSuffix() throws {
        let stubs = installer()
        try stubs.install(appID: "org.example.First", name: "Same", version: "1")
        let second = try stubs.install(appID: "org.example.Second", name: "Same", version: "1")
        #expect(second.lastPathComponent == "Same (org.example.Second).app")
        #expect(stubs.bundleURL(for: "org.example.Second")?.lastPathComponent == second.lastPathComponent)
    }

    @Test func reinstallReplacesInPlace() throws {
        let stubs = installer()
        let first = try stubs.install(appID: "org.example.Same", name: "Same", version: "1")
        let second = try stubs.install(
            appID: "org.example.Same", name: "Same", version: "2", iconPNG: try iconPNG())
        #expect(first.lastPathComponent == second.lastPathComponent)
        #expect(stubs.installedAppIDs() == ["org.example.Same"])
        let info = try plist(of: second)
        #expect(info["CFBundleShortVersionString"] as? String == "2")
        #expect(info["CFBundleIconFile"] as? String == "AppIcon")
    }
}
