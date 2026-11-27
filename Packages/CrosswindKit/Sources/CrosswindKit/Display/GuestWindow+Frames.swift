// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

extension GuestWindow {
    /// Writes a frame's damage into the back surface and returns the rects that decoded, plus the title bar color
    /// when this frame changed the window's top edge.
    ///
    /// Core Animation only re-reads a layer's IOSurface when it is handed a different one, so frames alternate between
    /// two surfaces. The back surface is one frame stale: last frame's damage is carried over from the front first.
    func compose(_ frame: Frame, front: IOSurface, back: IOSurface) -> ([DamageRect], TitlebarTint.Color?) {
        front.lock(options: .readOnly, seed: nil)
        back.lock(options: [], seed: nil)
        defer {
            back.unlock(options: [], seed: nil)
            front.unlock(options: .readOnly, seed: nil)
        }
        let stride = back.bytesPerRow
        for rect in previousDamage {
            for row in Int(rect.y)..<Int(rect.y + rect.height) {
                let offset = row * stride + Int(rect.x) * 4
                memcpy(back.baseAddress + offset, front.baseAddress + offset, Int(rect.width) * 4)
            }
        }
        var applied: [DamageRect] = []
        for rect in frame.damage where Self.decode(rect, into: back.baseAddress, stride: stride) {
            applied.append(rect)
        }
        // The title bar follows the app's top edge, read only when this frame changed it.
        let topChanged = !hasTint || applied.contains { $0.y < TitlebarTint.sensitiveRows }
        let sampled =
            topChanged
            ? TitlebarTint.topEdge(
                base: back.baseAddress, stride: stride, width: Int(frame.width), height: Int(frame.height)) : nil
        return (applied, sampled)
    }

    /// Copies one damage rect into the surface. Returns false (and draws nothing) if its pixels do not decode to
    /// exactly the rect's size.
    @discardableResult
    static func decode(_ rect: DamageRect, into base: UnsafeMutableRawPointer, stride: Int) -> Bool {
        guard let packed = RectCodec.unpack(width: rect.width, height: rect.height, pixels: rect.pixels) else {
            if DisplayLimits.violationLog.allow() {
                Log.display.warning("damage rect refused: payload does not decode")
            }
            return false
        }
        let w = Int(rect.width)
        packed.withUnsafeBytes { src in
            for row in 0..<Int(rect.height) {
                memcpy(base + (Int(rect.y) + row) * stride + Int(rect.x) * 4, src.baseAddress! + row * w * 4, w * 4)
            }
        }
        return true
    }
}
