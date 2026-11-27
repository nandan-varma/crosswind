// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// The color of a Linux window's top edge, so the Mac title bar can match the app's own header bar instead of
/// stacking a second bar above it (GNOME apps draw their own).
enum TitlebarTint {
    /// A color in the 0...1 sRGB range.
    struct Color: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        /// Relative luminance, enough to choose between a light and a dark title bar appearance.
        var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
        var isDark: Bool { luminance < 0.5 }

        var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

        func isClose(to other: Color, tolerance: Double = 0.02) -> Bool {
            abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
                && abs(blue - other.blue) <= tolerance
        }
    }

    /// The row sampled: not row 0, which can be an antialiased edge or a one-pixel border.
    static let sampleRow = 2
    /// Damage this close to the top can change the tint.
    static let sensitiveRows: UInt32 = 6

    /// The average of a few points along the top edge of a BGRA surface, away from its corners (window buttons and
    /// rounded corners live there). Nil when the surface is too small to sample.
    static func topEdge(base: UnsafeRawPointer, stride: Int, width: Int, height: Int) -> Color? {
        guard width >= 64, height > sampleRow else { return nil }
        let row = base + sampleRow * stride
        var totals = (red: 0.0, green: 0.0, blue: 0.0)
        let positions = [0.25, 0.4, 0.6, 0.75].map { Int(Double(width) * $0) }
        for x in positions {
            let pixel = row.load(fromByteOffset: x * 4, as: UInt32.self)  // BGRA, little endian
            totals.blue += Double(pixel & 0xFF)
            totals.green += Double((pixel >> 8) & 0xFF)
            totals.red += Double((pixel >> 16) & 0xFF)
        }
        let scale = 255 * Double(positions.count)
        return Color(red: totals.red / scale, green: totals.green / scale, blue: totals.blue / scale)
    }
}
