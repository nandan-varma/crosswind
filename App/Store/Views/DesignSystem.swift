// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CrosswindKit
import SwiftUI

// The store's shared visual vocabulary: the color each category and app carries, and the surface that cards sit on.

extension CatalogCategory {
    /// The color of the category's sidebar icon, as in the Mac App Store's sidebar.
    var tint: Color {
        switch self {
        case .audio: .pink
        case .audioVideo: .purple
        case .development: .orange
        case .education: .yellow
        case .game: .green
        case .graphics: .indigo
        case .network: .blue
        case .office: .teal
        case .science: .mint
        case .settings: .gray
        case .system: .cyan
        case .utility: .brown
        case .video: .red
        }
    }
}

/// The color an app's icon is "about", used to tint its hero card. Averaging an icon gives a muddy brown for
/// most multicolored icons, so the result is pulled toward a saturated, mid-brightness version of itself.
enum IconTint {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// The average color of the icon's visible pixels, adjusted to read well as a background; nil when the data is
    /// not an image or the icon is fully transparent.
    static func dominant(in data: Data) -> Color? {
        guard let image = CIImage(data: data), !image.extent.isInfinite, !image.extent.isEmpty else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let alpha = Double(pixel[3]) / 255
        guard alpha > 0.05 else { return nil }
        // The average includes transparent pixels as black; divide the alpha back out.
        let color = NSColor(
            srgbRed: min(Double(pixel[0]) / 255 / alpha, 1), green: min(Double(pixel[1]) / 255 / alpha, 1),
            blue: min(Double(pixel[2]) / 255 / alpha, 1), alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(hue: hue, saturation: max(saturation, 0.35), brightness: min(max(brightness, 0.5), 0.9))
    }
}

/// The resting and hovered look of a tile that opens something: a hairline edge, and a small lift under the pointer.
private struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.quaternary.opacity(hovering ? 1.4 : 1), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(hovering ? 0.14 : 0.07), lineWidth: 1))
            .shadow(color: .black.opacity(hovering ? 0.22 : 0), radius: 14, y: 8)
            .scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
            .animation(.smooth(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Puts the view on a rounded card that lifts slightly under the pointer.
    func cardSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}
