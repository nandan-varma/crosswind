// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Display limits")
struct DisplayLimitsTests {
    @Test("titles lose control, separator and bidi characters")
    func sanitizeStripsDangerousScalars() {
        let raw = "Save\u{202E}txt.exe\nFake\u{2066}Alert\u{2069}\u{0007}\u{2028}end\u{FEFF}"
        #expect(DisplayLimits.sanitize(raw, maxBytes: 1024) == "Savetxt.exeFakeAlertend")
    }

    @Test("titles are cut on a character boundary within the byte limit")
    func sanitizeTruncates() {
        // "é" is two bytes: "a" + "é" fills 3 bytes exactly; the next "é" would make 5.
        #expect(DisplayLimits.sanitize("aééé", maxBytes: 3) == "aé")
        #expect(DisplayLimits.sanitize(String(repeating: "x", count: 5000), maxBytes: 1024).utf8.count == 1024)
        #expect(DisplayLimits.sanitize("", maxBytes: 0) == "")
    }

    @Test("surfaces: edges accepted, past the edges refused")
    func surfaceEdges() throws {
        try DisplayLimits.checkSurface(width: 16_384, height: 4096, scale120: 120)
        try DisplayLimits.checkSurface(width: 1, height: 1, scale120: 60)
        try DisplayLimits.checkSurface(width: 1, height: 1, scale120: 960)
        #expect(throws: DisplayLimits.Violation.emptySurface) { try DisplayLimits.checkSurface(width: 0, height: 1, scale120: 120) }
        #expect(throws: DisplayLimits.Violation.surfaceTooLarge(width: 16_385, height: 1)) {
            try DisplayLimits.checkSurface(width: 16_385, height: 1, scale120: 120)
        }
        #expect(throws: DisplayLimits.Violation.surfaceTooLarge(width: 16_384, height: 4097)) {
            try DisplayLimits.checkSurface(width: 16_384, height: 4097, scale120: 120)
        }
        #expect(throws: DisplayLimits.Violation.scaleOutOfRange(59)) {
            try DisplayLimits.checkSurface(width: 10, height: 10, scale120: 59)
        }
        #expect(throws: DisplayLimits.Violation.scaleOutOfRange(961)) {
            try DisplayLimits.checkSurface(width: 10, height: 10, scale120: 961)
        }
    }

    @Test("damage must lie inside the surface, without overflow at the top of the range")
    func damageBounds() throws {
        let surface = (w: UInt32(100), h: UInt32(50))
        let fits = makeFrame(width: 100, height: 50, scale: 120, rects: [(x: 90, y: 40, w: 10, h: 10, bytes: 400)])
        try DisplayLimits.checkFrame(fits)

        // x + width wraps in UInt32 if computed naively; the check must still refuse it.
        let wrap = makeFrame(
            width: surface.w, height: surface.h, scale: 120,
            rects: [(x: UInt32.max - 2, y: 0, w: 10, h: 1, bytes: 40)])
        #expect(throws: DisplayLimits.Violation.damageOutOfBounds(index: 0)) { try DisplayLimits.checkFrame(wrap) }

        let empty = makeFrame(width: 100, height: 50, scale: 120, rects: [(x: 0, y: 0, w: 0, h: 5, bytes: 0)])
        #expect(throws: DisplayLimits.Violation.damageEmpty(index: 0)) { try DisplayLimits.checkFrame(empty) }
    }

    @Test("compressed payloads are bounded by the LZ4 worst case for their size")
    func payloadBound() {
        let raw = 4 * 4 * 4
        let limit = DisplayLimits.maxCompressedBytes(forRaw: raw)
        let ok = makeFrame(width: 16, height: 16, scale: 120, rects: [(x: 0, y: 0, w: 4, h: 4, bytes: limit)])
        #expect((try? DisplayLimits.checkFrame(ok)) != nil)
        let big = makeFrame(width: 16, height: 16, scale: 120, rects: [(x: 0, y: 0, w: 4, h: 4, bytes: limit + 1)])
        #expect(throws: DisplayLimits.Violation.damagePayloadTooLarge(index: 0)) { try DisplayLimits.checkFrame(big) }
    }

    @Test("too many damage rects are refused")
    func damageCount() {
        let rects = Array(repeating: (x: UInt32(0), y: UInt32(0), w: UInt32(1), h: UInt32(1), bytes: 4), count: 257)
        let frame = makeFrame(width: 10, height: 10, scale: 120, rects: rects)
        #expect(throws: DisplayLimits.Violation.tooManyDamageRects(257)) { try DisplayLimits.checkFrame(frame) }
    }

    @Test("cursors: name length, size and pixel count")
    func cursors() throws {
        let small: Crosswind_Display_Cursor = .with {
            $0.width = 2
            $0.height = 2
            $0.pixels = Data(count: 16)
        }
        try DisplayLimits.checkCursor(small)
        let hidden: Crosswind_Display_Cursor = .with { $0.name = "" }
        try DisplayLimits.checkCursor(hidden)
        let longName: Crosswind_Display_Cursor = .with { $0.name = String(repeating: "a", count: 65) }
        #expect((try? DisplayLimits.checkCursor(longName)) == nil)
        let mismatch: Crosswind_Display_Cursor = .with {
            $0.width = 2
            $0.height = 2
            $0.pixels = Data(count: 15)
        }
        #expect(throws: DisplayLimits.Violation.cursorPixelsMismatch) { try DisplayLimits.checkCursor(mismatch) }
        let huge: Crosswind_Display_Cursor = .with {
            $0.width = UInt32.max
            $0.height = UInt32.max
        }
        #expect((try? DisplayLimits.checkCursor(huge)) == nil)
    }

    @Test("window admission: duplicates, per-app and total caps, popup parents and depth")
    func windowAdmission() throws {
        var open: [UInt32: DisplayLimits.WindowAccount] = [:]
        open[1] = .init(app: "a", popupDepth: 0)
        #expect(throws: DisplayLimits.Violation.duplicateWindow(1)) {
            try DisplayLimits.admitOpen(id: 1, isPopup: false, parent: 0, app: "a", existing: open)
        }

        // Popups must hang off a window of the same app, and chains are bounded.
        #expect(throws: DisplayLimits.Violation.unknownParent(99)) {
            try DisplayLimits.admitOpen(id: 2, isPopup: true, parent: 99, app: "a", existing: open)
        }
        #expect(throws: DisplayLimits.Violation.parentFromOtherApp(1)) {
            try DisplayLimits.admitOpen(id: 2, isPopup: true, parent: 1, app: "b", existing: open)
        }
        var depth = 0
        var id: UInt32 = 10
        var parent: UInt32 = 1
        while true {
            do {
                depth = try DisplayLimits.admitOpen(id: id, isPopup: true, parent: parent, app: "a", existing: open)
            } catch {
                #expect(error as? DisplayLimits.Violation == .popupTooDeep(DisplayLimits.maxPopupDepth + 1))
                break
            }
            open[id] = .init(app: "a", popupDepth: depth)
            parent = id
            id += 1
        }
        #expect(depth == DisplayLimits.maxPopupDepth)

        // Per app and total caps.
        var full: [UInt32: DisplayLimits.WindowAccount] = [:]
        for i in 0..<UInt32(DisplayLimits.maxWindowsPerApp) { full[i] = .init(app: "a", popupDepth: 0) }
        #expect(throws: DisplayLimits.Violation.tooManyWindows) {
            try DisplayLimits.admitOpen(id: 500, isPopup: false, parent: 0, app: "a", existing: full)
        }
        _ = try DisplayLimits.admitOpen(id: 500, isPopup: false, parent: 0, app: "b", existing: full)
        for i in 1000..<UInt32(1000 + DisplayLimits.maxWindowsTotal - full.count) {
            full[i] = .init(app: "b\(i)", popupDepth: 0)
        }
        #expect(full.count == DisplayLimits.maxWindowsTotal)
        #expect(throws: DisplayLimits.Violation.tooManyWindows) {
            try DisplayLimits.admitOpen(id: 501, isPopup: false, parent: 0, app: "c", existing: full)
        }
    }

    @Test("random frames: anything accepted satisfies every invariant")
    func randomFramesFuzz() throws {
        var rng = SplitMix64(seed: 0xF00D)
        var accepted = 0
        for _ in 0..<20_000 {
            let width = Bool.random(using: &rng) ? EdgeValues.sizes.randomElement(using: &rng)! : UInt32.random(in: 0...20_000, using: &rng)
            let height = Bool.random(using: &rng) ? EdgeValues.sizes.randomElement(using: &rng)! : UInt32.random(in: 0...20_000, using: &rng)
            let scale = Bool.random(using: &rng) ? EdgeValues.scales.randomElement(using: &rng)! : UInt32.random(in: 0...1000, using: &rng)
            let count = Int.random(in: 0...4, using: &rng)
            let rects = (0..<count).map { _ -> (x: UInt32, y: UInt32, w: UInt32, h: UInt32, bytes: Int) in
                (
                    x: EdgeValues.sizes.randomElement(using: &rng)!, y: UInt32.random(in: 0...20_000, using: &rng),
                    w: UInt32.random(in: 0...20_000, using: &rng), h: EdgeValues.sizes.randomElement(using: &rng)!,
                    bytes: Int.random(in: 0...2048, using: &rng)
                )
            }
            let frame = makeFrame(width: width, height: height, scale: scale, rects: rects)
            guard (try? DisplayLimits.checkFrame(frame)) != nil else { continue }
            accepted += 1
            #expect(width > 0 && height > 0 && width <= 16_384 && height <= 16_384)
            #expect(UInt64(width) * UInt64(height) <= DisplayLimits.maxSurfacePixels)
            #expect((60...960).contains(scale))
            for rect in frame.damage {
                #expect(UInt64(rect.x) + UInt64(rect.width) <= UInt64(width))
                #expect(UInt64(rect.y) + UInt64(rect.height) <= UInt64(height))
                // Payloads are zero bytes here, which are not valid LZ4 for these sizes: decoding must refuse them.
                #expect(RectCodec.unpack(width: rect.width, height: rect.height, pixels: rect.pixels) == nil)
            }
        }
        // The generator is biased toward refusals; make sure some frames did get through.
        #expect(accepted > 0)
    }
}

@Suite("Rect codec")
struct RectCodecTests {
    @Test("LZ4 rects round trip at their exact size")
    func roundTrip() throws {
        var rng = SplitMix64(seed: 7)
        for (w, h) in [(1, 1), (3, 5), (64, 16), (255, 2)] {
            let raw = Data(rng.bytes(w * h * 4))
            let packed = try #require(RectCodec.pack(raw))
            let out = RectCodec.unpack(width: UInt32(w), height: UInt32(h), pixels: packed)
            #expect(out == raw)
        }
    }

    @Test("a payload that decodes to the wrong size is refused")
    func wrongSize() throws {
        let raw = Data(repeating: 0xAB, count: 4 * 4 * 4)
        let packed = try #require(RectCodec.pack(raw))
        #expect(RectCodec.unpack(width: 4, height: 4, pixels: packed) != nil)
        #expect(RectCodec.unpack(width: 4, height: 5, pixels: packed) == nil)
        #expect(RectCodec.unpack(width: 4, height: 3, pixels: packed) == nil)
    }

    @Test("degenerate and overflowing sizes are refused without allocating")
    func degenerateSizes() {
        let payload = Data([0, 0, 0, 0])
        #expect(RectCodec.unpack(width: 0, height: 10, pixels: payload) == nil)
        #expect(RectCodec.unpack(width: UInt32.max, height: UInt32.max, pixels: payload) == nil)
        #expect(RectCodec.unpack(width: 16_384, height: 16_384, pixels: payload) == nil)
        #expect(RectCodec.unpack(width: 4, height: 4, pixels: Data()) == nil)
    }

    @Test("random compressed bytes never decode to a wrong-sized rect")
    func randomPayloadsFuzz() {
        var rng = SplitMix64(seed: 0xBEEF)
        for _ in 0..<5_000 {
            let w = UInt32.random(in: 0...70, using: &rng)
            let h = UInt32.random(in: 0...70, using: &rng)
            let payload = Data(rng.bytes(Int.random(in: 0...400, using: &rng)))
            if let out = RectCodec.unpack(width: w, height: h, pixels: payload) {
                #expect(out.count == Int(w) * Int(h) * 4)
            }
        }
    }
}
