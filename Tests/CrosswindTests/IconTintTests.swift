// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import Testing

@testable import Crosswind

@Suite struct IconTintTests {
    private func png(_ color: NSColor, size: Int = 16) throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func hue(_ color: Color) -> CGFloat {
        var hue: CGFloat = 0
        NSColor(color).usingColorSpace(.sRGB)?.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        return hue
    }

    @Test func aSolidIconYieldsItsOwnHue() throws {
        let orange = try #require(IconTint.dominant(in: try png(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))))
        #expect(abs(hue(orange) - 0.083) < 0.03)
    }

    @Test func aTransparentIconHasNoTint() throws {
        #expect(IconTint.dominant(in: try png(.clear)) == nil)
    }

    @Test func dataThatIsNotAnImageHasNoTint() {
        #expect(IconTint.dominant(in: Data("not an image".utf8)) == nil)
    }

    @Test func aNearlyGreyIconIsGivenEnoughColorToReadAsABackground() throws {
        let tint = try #require(IconTint.dominant(in: try png(NSColor(white: 0.5, alpha: 1))))
        var saturation: CGFloat = 0
        NSColor(tint).usingColorSpace(.sRGB)?.getHue(nil, saturation: &saturation, brightness: nil, alpha: nil)
        #expect(saturation >= 0.34)
    }
}
