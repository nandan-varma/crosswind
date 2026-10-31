// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum IconRendererError: Error {
    case undecodableImage
    case renderFailed
    case writeFailed(String)
}

/// Turns any source image into a macOS-style `.iconset` directory, ready for `iconutil -c icns`.
///
/// The base is a transparent 1024-pt canvas. Artwork sits in the standard 824-pt grid, centred. Squarish,
/// fully opaque sources are clipped to a continuous-corner rounded rect; anything with transparency is drawn as is.
/// Both get the same soft drop shadow. Only CoreGraphics and ImageIO are used.
public enum IconRenderer {
    static let canvasSize = 1024
    static let gridSize: CGFloat = 824
    static let cornerRatio: CGFloat = 0.2237
    static let shadowOffset = CGSize(width: 0, height: -10)
    static let shadowBlur: CGFloat = 20
    static let shadowAlpha: CGFloat = 0.3

    /// Iconset file names and their pixel sizes.
    static let entries: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    /// Renders `pngData` into `<tmp>/<uuid>/AppIcon.iconset` and returns the `.iconset` URL.
    /// The caller owns the parent directory `<tmp>/<uuid>` and should delete it when done.
    public static func iconSet(from pngData: Data) throws -> URL {
        let source = try decode(pngData)
        let base = try renderBase(source)

        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        let set = root.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
            for (name, pixels) in entries {
                let image = try scaled(base, to: pixels)
                try writePNG(image, to: set.appending(path: name))
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        return set
    }

    // MARK: Rendering

    private static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw IconRendererError.undecodableImage }
        return image
    }

    private static func renderBase(_ source: CGImage) throws -> CGImage {
        let context = try makeContext(size: canvasSize)
        let grid = CGRect(x: 0, y: 0, width: gridSize, height: gridSize)
            .offsetBy(dx: (CGFloat(canvasSize) - gridSize) / 2, dy: (CGFloat(canvasSize) - gridSize) / 2)
        let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadowAlpha)

        if isSquarish(source), cornersOpaque(source) {
            let path = CGPath(
                roundedRect: grid, cornerWidth: gridSize * cornerRatio, cornerHeight: gridSize * cornerRatio,
                transform: nil)
            // Opaque fill casts the shadow; the artwork then covers it inside the clip.
            context.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.addPath(path)
            context.fillPath()

            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.draw(source, in: aspectFill(source, into: grid))
            context.restoreGState()
        } else {
            context.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            context.draw(source, in: aspectFit(source, into: grid))
        }

        guard let image = context.makeImage() else { throw IconRendererError.renderFailed }
        return image
    }

    private static func scaled(_ base: CGImage, to pixels: Int) throws -> CGImage {
        let context = try makeContext(size: pixels)
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let image = context.makeImage() else { throw IconRendererError.renderFailed }
        return image
    }

    private static func makeContext(size: Int) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw IconRendererError.renderFailed }
        return context
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw IconRendererError.writeFailed(url.lastPathComponent) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw IconRendererError.writeFailed(url.lastPathComponent)
        }
    }

    // MARK: Geometry and classification

    private static func isSquarish(_ image: CGImage) -> Bool {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        return abs(width - height) <= 0.1 * max(width, height)
    }

    /// Aspect-fit: the whole image inside `rect`, centred.
    private static func aspectFit(_ image: CGImage, into rect: CGRect) -> CGRect {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        return centered(CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale), in: rect)
    }

    /// Aspect-fill: covers `rect` completely, centred; overflow is clipped by the caller.
    private static func aspectFill(_ image: CGImage, into rect: CGRect) -> CGRect {
        let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        return centered(CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale), in: rect)
    }

    private static func centered(_ size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// True when all four corner pixels are fully opaque.
    private static func cornersOpaque(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
            return corners.allSatisfy { column, row in buffer[(row * width + column) * 4 + 3] == 255 }
        }
    }
}
