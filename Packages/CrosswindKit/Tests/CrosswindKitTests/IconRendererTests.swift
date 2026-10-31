// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CrosswindKit

/// Decoded pixels, premultiplied RGBA, row-major from the top-left.
private struct RGBAImage {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}

@Suite struct IconRendererTests {
    /// PNG of `size` pixels with `draw` applied to a transparent sRGB canvas.
    private func makePNG(size: Int, draw: (CGContext) -> Void) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        draw(context)
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func redSquarePNG() throws -> Data {
        try makePNG(size: 128) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        }
    }

    private func transparentCirclePNG() throws -> Data {
        try makePNG(size: 128) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
    }

    /// RGBA bytes of a PNG at `url`, with dimensions.
    private func pixels(of url: URL) throws -> RGBAImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return RGBAImage(width: image.width, height: image.height, rgba: bytes)
    }

    /// Alpha of the pixel at (x, y) counted from the top-left.
    private func alpha(_ image: RGBAImage, column: Int, row: Int) -> UInt8 {
        image.rgba[(row * image.width + column) * 4 + 3]
    }

    /// Renders `png`, runs `body` on the resulting `.iconset`, then removes the output.
    private func withIconSet(_ png: Data, _ body: (URL) throws -> Void) throws {
        let set = try IconRenderer.iconSet(from: png)
        defer { try? FileManager.default.removeItem(at: set.deletingLastPathComponent()) }
        try body(set)
    }

    private func expectExactSizes(_ set: URL) throws {
        #expect(set.lastPathComponent == "AppIcon.iconset")
        let expected: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        let files = try FileManager.default.contentsOfDirectory(atPath: set.path)
        #expect(files.count == 10)
        for (name, size) in expected {
            let image = try pixels(of: set.appending(path: name))
            #expect(image.width == size, "\(name) width")
            #expect(image.height == size, "\(name) height")
        }
    }

    @Test func squareOpaqueArtworkIsRoundedWithTransparentCorners() throws {
        try withIconSet(redSquarePNG()) { set in
            try expectExactSizes(set)
            let base = try pixels(of: set.appending(path: "icon_512x512@2x.png"))
            #expect(alpha(base, column: 0, row: 0) == 0)
            #expect(alpha(base, column: 1023, row: 0) == 0)
            #expect(alpha(base, column: 0, row: 1023) == 0)
            #expect(alpha(base, column: 1023, row: 1023) == 0)
            #expect(alpha(base, column: 512, row: 512) == 255)
        }
    }

    @Test func transparentArtworkIsDrawnWithoutClipping() throws {
        try withIconSet(transparentCirclePNG()) { set in
            try expectExactSizes(set)
            let base = try pixels(of: set.appending(path: "icon_512x512@2x.png"))
            // The circle fills the 824 grid: the centre is opaque and the canvas corners stay transparent.
            #expect(alpha(base, column: 512, row: 512) == 255)
            #expect(alpha(base, column: 0, row: 0) == 0)
            #expect(alpha(base, column: 1023, row: 1023) == 0)
        }
    }

    @Test func undecodableDataThrows() {
        #expect(throws: IconRendererError.self) { try IconRenderer.iconSet(from: Data("not an image".utf8)) }
    }

}
