// SPDX-License-Identifier: AGPL-3.0-or-later
import Compression
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Compatibility canvas")
struct CompatCanvasTests {
    /// An LZ4_RAW rectangle filled with one BGRA colour.
    private static func rect(x: UInt32, y: UInt32, width: UInt32, height: UInt32, bgra: [UInt8]) -> Crosswind_Display_Rect {
        let raw = (0..<Int(width * height)).flatMap { _ in bgra }
        var packed = [UInt8](repeating: 0, count: raw.count + 64)
        let size = packed.withUnsafeMutableBytes { output in
            raw.withUnsafeBytes { input in
                compression_encode_buffer(
                    output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                    input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return .with {
            $0.x = x
            $0.y = y
            $0.width = width
            $0.height = height
            $0.pixels = Data(packed.prefix(size))
        }
    }

    private static func frame(width: UInt32, height: UInt32, damage: [Crosswind_Display_Rect]) -> Crosswind_Display_Frame {
        .with {
            $0.width = width
            $0.height = height
            $0.damage = damage
        }
    }

    private static func pixel(_ canvas: Canvas, x: Int, y: Int) -> [UInt8] {
        let offset = (y * canvas.width + x) * 4
        return Array(canvas.pixels[offset..<offset + 4])
    }

    // Apple's LZ4_RAW encoder returns nothing for inputs this small, so every rectangle here is at least 4x4.
    @Test("damage rectangles are decoded into place and later frames keep earlier pixels")
    func assembly() {
        var canvas = Canvas()
        let red: [UInt8] = [0, 0, 255, 255]
        let blue: [UInt8] = [255, 0, 0, 255]
        let first = canvas.apply(
            Self.frame(width: 8, height: 4, damage: [Self.rect(x: 0, y: 0, width: 8, height: 4, bgra: red)]))
        let second = canvas.apply(
            Self.frame(width: 8, height: 4, damage: [Self.rect(x: 4, y: 0, width: 4, height: 4, bgra: blue)]))
        #expect(first)
        #expect(second)
        #expect(Self.pixel(canvas, x: 0, y: 0) == red)
        #expect(Self.pixel(canvas, x: 3, y: 3) == red)
        #expect(Self.pixel(canvas, x: 4, y: 0) == blue)
        #expect(Self.pixel(canvas, x: 7, y: 3) == blue)
        #expect(canvas.pixels.count == 8 * 4 * 4)
    }

    @Test("a size change starts a blank canvas")
    func resize() {
        var canvas = Canvas()
        canvas.apply(Self.frame(width: 4, height: 4, damage: [Self.rect(x: 0, y: 0, width: 4, height: 4, bgra: [9, 9, 9, 255])]))
        canvas.apply(Self.frame(width: 3, height: 1, damage: []))
        #expect(canvas.width == 3)
        #expect(canvas.height == 1)
        #expect(canvas.pixels == [UInt8](repeating: 0, count: 12))
    }

    @Test("out-of-bounds and corrupt rectangles are rejected, the rest still applies")
    func malformed() {
        var canvas = Canvas()
        let bad = Self.rect(x: 6, y: 0, width: 4, height: 4, bgra: [1, 2, 3, 4])
        var corrupt = Crosswind_Display_Rect()
        corrupt.width = 4
        corrupt.height = 4
        corrupt.pixels = Data([0xFF, 0xFF, 0xFF])
        let good = Self.rect(x: 0, y: 0, width: 4, height: 4, bgra: [7, 7, 7, 255])
        let complete = canvas.apply(Self.frame(width: 8, height: 4, damage: [bad, corrupt, good]))
        #expect(!complete)
        #expect(Self.pixel(canvas, x: 0, y: 0) == [7, 7, 7, 255])
        #expect(Self.pixel(canvas, x: 4, y: 0) == [0, 0, 0, 0])
    }

    @Test("a single colour is flat, a checker pattern is not")
    func flatDetection() {
        let flat = [UInt8](repeating: 128, count: 64 * 64 * 4)
        #expect(PixelStatistics.isFlat(flat, width: 64, height: 64))
        var checker = [UInt8](repeating: 0, count: 64 * 64 * 4)
        for index in 0..<(64 * 64) where (index / 64 + index % 64) % 2 == 0 {
            checker[index * 4] = 255
            checker[index * 4 + 1] = 255
            checker[index * 4 + 2] = 255
        }
        #expect(!PixelStatistics.isFlat(checker, width: 64, height: 64))
        #expect(PixelStatistics.isFlat([], width: 0, height: 0))
    }

    @Test("a canvas writes a readable PNG")
    func png() throws {
        var canvas = Canvas()
        canvas.apply(Self.frame(width: 8, height: 8, damage: [Self.rect(x: 0, y: 0, width: 8, height: 8, bgra: [1, 2, 3, 255])]))
        let url = FileManager.default.temporaryDirectory.appending(path: "compat-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try canvas.writePNG(to: url)
        let header = try Data(contentsOf: url).prefix(4)
        #expect(Array(header) == [0x89, 0x50, 0x4E, 0x47])
    }
}
