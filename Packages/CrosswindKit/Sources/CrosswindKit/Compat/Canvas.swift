// SPDX-License-Identifier: AGPL-3.0-or-later
import Compression
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A window's pixels (premultiplied BGRA, 4 bytes per pixel) assembled from the guest's damage rectangles,
/// the same way `GuestWindow` assembles them on screen, but without a Mac window.
public struct Canvas: Sendable, Equatable {
    public private(set) var width = 0
    public private(set) var height = 0
    public private(set) var pixels: [UInt8] = []

    public init() {}

    /// Applies one frame. A size change starts a blank canvas. Returns false when a damage rectangle was
    /// malformed or did not decode; the other rectangles are still applied.
    @discardableResult
    public mutating func apply(_ frame: Crosswind_Display_Frame) -> Bool {
        let newWidth = Int(frame.width)
        let newHeight = Int(frame.height)
        if newWidth != width || newHeight != height || pixels.count != newWidth * newHeight * 4 {
            width = newWidth
            height = newHeight
            pixels = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        }
        var complete = true
        for rect in frame.damage where !blit(rect) {
            complete = false
        }
        return complete
    }

    /// Decodes one LZ4_RAW rectangle and copies it into place. Returns false if it is out of bounds or corrupt.
    private mutating func blit(_ rect: Crosswind_Display_Rect) -> Bool {
        let x = Int(rect.x)
        let y = Int(rect.y)
        let w = Int(rect.width)
        let h = Int(rect.height)
        guard w > 0, h > 0, x + w <= width, y + h <= height else { return false }
        let expected = w * h * 4
        let packed = rect.pixels
        guard !packed.isEmpty else { return false }
        var decoded = [UInt8](repeating: 0, count: expected)
        let count = decoded.withUnsafeMutableBytes { output in
            packed.withUnsafeBytes { input in
                compression_decode_buffer(
                    output.baseAddress!.assumingMemoryBound(to: UInt8.self), expected,
                    input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard count == expected else { return false }
        let stride = width * 4
        pixels.withUnsafeMutableBytes { destination in
            decoded.withUnsafeBytes { source in
                for row in 0..<h {
                    memcpy(
                        destination.baseAddress! + (y + row) * stride + x * 4,
                        source.baseAddress! + row * w * 4, w * 4)
                }
            }
        }
        return true
    }

    /// True when the sampled luma varies little, e.g. a blank or single-colour window.
    public var isFlat: Bool {
        PixelStatistics.isFlat(pixels, width: width, height: height)
    }

    /// Writes the canvas as a PNG (alpha ignored).
    public func writePNG(to url: URL) throws {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            throw CompatError.pngFailed("empty canvas")
        }
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap, provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CompatError.pngFailed("cannot create image") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CompatError.pngFailed("cannot write \(url.path)") }
    }
}

public enum PixelStatistics {
    /// Variance of sampled luma below `threshold` (in 8-bit units squared) counts as flat.
    public static func isFlat(_ pixels: [UInt8], width: Int, height: Int, threshold: Double = 16) -> Bool {
        let count = width * height
        guard count > 0, pixels.count == count * 4 else { return true }
        let step = max(1, count / 4096)
        var sum = 0.0
        var squares = 0.0
        var samples = 0
        var index = 0
        while index < count {
            let offset = index * 4
            let luma = 0.114 * Double(pixels[offset]) + 0.587 * Double(pixels[offset + 1])
                + 0.299 * Double(pixels[offset + 2])
            sum += luma
            squares += luma * luma
            samples += 1
            index += step
        }
        let mean = sum / Double(samples)
        return squares / Double(samples) - mean * mean < threshold
    }
}
