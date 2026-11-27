// SPDX-License-Identifier: AGPL-3.0-or-later
// Generates Crosswind's app icon set and menu bar glyph. Run: swift design/make-icons.swift <output-assets-dir>
// The artwork is drawn here, so the icon is reproducible and reviewable as code.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The two crossing wind strokes, in a 64-unit box (the same shape as the website's favicon), as paths in canvas
/// coordinates with y pointing up.
func windPaths() -> [CGPath] {
    func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * 14 + 64, y: canvas - (y * 14 + 64)) }
    let upper = CGMutablePath()
    upper.move(to: map(13, 41))
    upper.addCurve(to: map(32, 24), control1: map(24, 39), control2: map(28, 30))
    upper.addCurve(to: map(51, 18), control1: map(36, 18), control2: map(43, 16))
    let lower = CGMutablePath()
    lower.move(to: map(13, 29))
    lower.addCurve(to: map(32, 44), control1: map(22, 31), control2: map(28, 38))
    lower.addCurve(to: map(51, 50), control1: map(36, 50), control2: map(43, 52))
    return [upper, lower]
}

/// A superellipse (exponent 5): the continuous-curvature corner macOS icons use, not a plain rounded rectangle.
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let steps = 360
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + rect.width / 2 * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / n)
        let y = rect.midY + rect.height / 2 * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / n)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // macOS icon grid: an 824-point squircle centered in the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = squirclePath(in: body)

    // Soft ground shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x000000, 0.35))
    context.setFillColor(rgb(0x1B2A6B))
    context.addPath(squircle)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()

    // Body: sky blue at the top left, through royal blue, into violet.
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [rgb(0x5AC8FA), rgb(0x1F6FEB), rgb(0x6E40F5)] as CFArray, locations: [0, 0.55, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 220, y: 924), end: CGPoint(x: 820, y: 100), options: [])

    // A faint window pane the wind passes through: Linux windows arriving on the Mac.
    let pane = CGPath(
        roundedRect: CGRect(x: 262, y: 300, width: 500, height: 424), cornerWidth: 54, cornerHeight: 54, transform: nil)
    context.setFillColor(rgb(0xFFFFFF, 0.14))
    context.addPath(pane)
    context.fillPath()
    context.setStrokeColor(rgb(0xFFFFFF, 0.38))
    context.setLineWidth(5)
    context.addPath(pane)
    context.strokePath()
    for (index, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        context.setFillColor(rgb(UInt32(color), 0.95))
        context.fillEllipse(in: CGRect(x: 308 + CGFloat(index) * 44, y: 664, width: 26, height: 26))
    }

    // The wind: two crossing strokes with a soft shadow, filled with a gradient that thins toward the tails.
    let wind = CGGradient(
        colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xE9F3FF)] as CFArray, locations: [0, 1])!
    for path in windPaths() {
        let outline = path.copy(strokingWithWidth: 80, lineCap: .round, lineJoin: .round, miterLimit: 10)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x0A1F66, 0.45))
        context.setFillColor(rgb(0xFFFFFF))
        context.addPath(outline)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.drawLinearGradient(wind, start: CGPoint(x: 250, y: 780), end: CGPoint(x: 780, y: 240), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    // Glass highlight across the top.
    let sheen = CGGradient(
        colorsSpace: space, colors: [rgb(0xFFFFFF, 0.34), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    context.restoreGState()

    // Hairline edge.
    context.setStrokeColor(rgb(0xFFFFFF, 0.28))
    context.setLineWidth(3)
    context.addPath(squircle)
    context.strokePath()
}

func writePNG(size: Int, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: context)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

/// The menu bar glyph: the wind strokes alone, black on transparent, as a vector PDF for a template image.
func writeGlyph(to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    context.scaleBy(x: 18 / canvas, y: 18 / canvas)
    // Re-center the strokes (they span x 246...778) and thicken them for small sizes.
    context.translateBy(x: 0, y: 0)
    context.setLineCap(.round)
    context.setLineWidth(110)
    context.setStrokeColor(CGColor(gray: 0, alpha: 1))
    for path in windPaths() {
        context.addPath(path)
        context.strokePath()
    }
    context.endPDFPage()
    context.closePDF()
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets")
let fm = FileManager.default
let iconset = output.appending(path: "AppIcon.appiconset")
let glyphset = output.appending(path: "MenuBarIcon.imageset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: glyphset, withIntermediateDirectories: true)

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        writePNG(size: base * scale, to: iconset.appending(path: name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let info: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appending(path: "Contents.json"))

writeGlyph(to: glyphset.appending(path: "MenuBarIcon.pdf"))
let glyphInfo: [String: Any] = [
    "images": [["idiom": "universal", "filename": "MenuBarIcon.pdf"]],
    "info": ["version": 1, "author": "xcode"],
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
]
try JSONSerialization.data(withJSONObject: glyphInfo, options: [.prettyPrinted, .sortedKeys])
    .write(to: glyphset.appending(path: "Contents.json"))
print("wrote \(iconset.path) and \(glyphset.path)")
