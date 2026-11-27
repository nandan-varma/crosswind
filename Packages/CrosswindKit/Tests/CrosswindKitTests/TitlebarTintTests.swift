// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import CrosswindKit

@Suite struct TitlebarTintTests {
    /// A BGRA surface whose every pixel is one color.
    private func surface(width: Int = 200, height: Int = 20, bgra: UInt32) -> [UInt32] {
        [UInt32](repeating: bgra, count: width * height)
    }

    private func sample(_ pixels: [UInt32], width: Int = 200, height: Int = 20) -> TitlebarTint.Color? {
        pixels.withUnsafeBytes {
            TitlebarTint.topEdge(base: $0.baseAddress!, stride: width * 4, width: width, height: height)
        }
    }

    @Test func aSolidTopEdgeIsReadBack() throws {
        // BGRA little endian: 0xAARRGGBB with red 0x30, green 0x60, blue 0x90.
        let color = try #require(sample(surface(bgra: 0xFF30_6090)))
        #expect(color.isClose(to: .init(red: 0x30 / 255.0, green: 0x60 / 255.0, blue: 0x90 / 255.0), tolerance: 0.005))
    }

    @Test func lightAndDarkEdgesChooseTheMatchingAppearance() throws {
        #expect(try #require(sample(surface(bgra: 0xFF20_2020))).isDark)
        #expect(try !#require(sample(surface(bgra: 0xFFF0_F0F0))).isDark)
    }

    @Test func tinySurfacesAreNotSampled() {
        #expect(sample(surface(width: 32, height: 20, bgra: 0xFF00_0000), width: 32) == nil)
        #expect(sample(surface(height: 2, bgra: 0xFF00_0000), height: 2) == nil)
    }

    @Test func nearbyColorsCountAsTheSameSoTheTitleBarDoesNotFlicker() {
        let a = TitlebarTint.Color(red: 0.2, green: 0.2, blue: 0.2)
        #expect(a.isClose(to: .init(red: 0.21, green: 0.2, blue: 0.19)))
        #expect(!a.isClose(to: .init(red: 0.3, green: 0.2, blue: 0.2)))
    }
}
