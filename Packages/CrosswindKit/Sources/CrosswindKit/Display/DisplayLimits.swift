// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Hard limits on what the guest may ask the host to allocate or draw. The guest is untrusted: every number in a
/// display message is checked against these before it is used. A violation drops the message and is logged
/// (rate limited); it never crashes the host. Limits are listed in docs/security.md.
public enum DisplayLimits {
    public static let maxWindowsPerApp = 32
    public static let maxWindowsTotal = 128
    /// Popup chains (popup of a popup of ...) deeper than this are refused.
    public static let maxPopupDepth = 8
    public static let maxSurfaceSide: UInt32 = 16_384
    /// 64 Mpx: a 16384 x 4096 surface is the largest shape that fits.
    public static let maxSurfacePixels: UInt64 = 64 << 20
    public static let scale120Range: ClosedRange<UInt32> = 60...960
    public static let maxDamageRectsPerFrame = 256
    public static let maxCursorSide: UInt32 = 512
    public static let maxCursorNameBytes = 64
    public static let maxTitleBytes = 1024
    public static let maxIdentifierBytes = 256

    /// Violations are logged at most this often (burst 5, then one per second).
    public static let violationLog = RateLimiter(perSecond: 1, burst: 5)

    /// Why a message was refused. Only for logs and tests.
    public enum Violation: Error, Equatable, CustomStringConvertible {
        case emptySurface
        case surfaceTooLarge(width: UInt32, height: UInt32)
        case scaleOutOfRange(UInt32)
        case tooManyDamageRects(Int)
        case damageEmpty(index: Int)
        case damageOutOfBounds(index: Int)
        case damagePayloadTooLarge(index: Int)
        case cursorTooLarge(width: UInt32, height: UInt32)
        case cursorPixelsMismatch
        case tooManyWindows
        case duplicateWindow(UInt32)
        case unknownParent(UInt32)
        case parentFromOtherApp(UInt32)
        case popupTooDeep(Int)

        public var description: String {
            switch self {
            case .emptySurface: "empty surface"
            case .surfaceTooLarge(let w, let h): "surface \(w)x\(h) exceeds limits"
            case .scaleOutOfRange(let s): "scale_120 \(s) out of range"
            case .tooManyDamageRects(let n): "\(n) damage rects"
            case .damageEmpty(let i): "damage rect \(i) is empty"
            case .damageOutOfBounds(let i): "damage rect \(i) outside the surface"
            case .damagePayloadTooLarge(let i): "damage rect \(i) payload too large"
            case .cursorTooLarge(let w, let h): "cursor \(w)x\(h) exceeds limits"
            case .cursorPixelsMismatch: "cursor pixels do not match its size"
            case .tooManyWindows: "too many windows"
            case .duplicateWindow(let id): "window \(id) is already open"
            case .unknownParent(let id): "popup parent \(id) is not open"
            case .parentFromOtherApp(let id): "popup parent \(id) belongs to another app"
            case .popupTooDeep(let d): "popup depth \(d) exceeds limit"
            }
        }
    }

    // MARK: Strings

    /// Window titles and identifiers come from the guest. Control characters, line and paragraph separators and
    /// bidi overrides/isolates are removed (they can reorder or hide text in a title bar), and the result is cut to
    /// `maxBytes` UTF-8 bytes on a character boundary. Titles are not prefixed or styled: a guest window is always
    /// an ordinary app window with the stub's own Dock identity, so a title cannot add a system-looking element.
    public static func sanitize(_ raw: String, maxBytes: Int) -> String {
        var out = ""
        var used = 0
        for scalar in raw.unicodeScalars {
            if isStrippedInTitle(scalar) { continue }
            let size = scalar.utf8.count
            if used + size > maxBytes { break }
            out.unicodeScalars.append(scalar)
            used += size
        }
        return out
    }

    static func isStrippedInTitle(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator, .unassigned, .surrogate: return true
        default: break
        }
        switch scalar.value {
        case 0x061C,  // arabic letter mark
            0x200E, 0x200F,  // LRM, RLM
            0x202A...0x202E,  // LRE, RLE, PDF, LRO, RLO
            0x2066...0x2069,  // LRI, RLI, FSI, PDI
            0xFEFF:  // byte order mark
            return true
        default:
            return false
        }
    }

    // MARK: Surfaces and frames

    public static func checkSurface(width: UInt32, height: UInt32, scale120: UInt32) throws(Violation) {
        guard width > 0, height > 0 else { throw .emptySurface }
        guard width <= maxSurfaceSide, height <= maxSurfaceSide,
            UInt64(width) * UInt64(height) <= maxSurfacePixels
        else {
            throw .surfaceTooLarge(width: width, height: height)
        }
        guard scale120Range.contains(scale120) else { throw .scaleOutOfRange(scale120) }
    }

    /// Bytes of a `width` x `height` BGRA rect, or nil when it overflows or exceeds the surface limit.
    public static func rectBytes(width: UInt32, height: UInt32) -> Int? {
        let pixels = UInt64(width) * UInt64(height)  // cannot overflow: both factors are below 2^32
        guard pixels <= maxSurfacePixels else { return nil }
        return Int(pixels * 4)
    }

    /// The most a valid LZ4 raw block of `raw` bytes can occupy (literal-only worst case plus headers).
    public static func maxCompressedBytes(forRaw raw: Int) -> Int {
        raw + raw / 255 + 64
    }

    /// Checks a whole frame: surface size and scale, then every damage rect (inside the surface, non-empty,
    /// compressed payload within the LZ4 bound for its size). The decompressed size is checked when it is unpacked.
    public static func checkFrame(_ frame: Crosswind_Display_Frame) throws(Violation) {
        try checkSurface(width: frame.width, height: frame.height, scale120: frame.scale120)
        guard frame.damage.count <= maxDamageRectsPerFrame else { throw .tooManyDamageRects(frame.damage.count) }
        for (index, rect) in frame.damage.enumerated() {
            guard rect.width > 0, rect.height > 0 else { throw .damageEmpty(index: index) }
            guard UInt64(rect.x) + UInt64(rect.width) <= UInt64(frame.width),
                UInt64(rect.y) + UInt64(rect.height) <= UInt64(frame.height)
            else {
                throw .damageOutOfBounds(index: index)
            }
            guard let raw = rectBytes(width: rect.width, height: rect.height),
                rect.pixels.count <= maxCompressedBytes(forRaw: raw)
            else {
                throw .damagePayloadTooLarge(index: index)
            }
        }
    }

    public static func checkCursor(_ cursor: Crosswind_Display_Cursor) throws(Violation) {
        guard cursor.name.utf8.count <= maxCursorNameBytes else {
            throw .cursorTooLarge(width: cursor.width, height: cursor.height)
        }
        guard cursor.pixels.isEmpty || (cursor.width > 0 && cursor.height > 0) else {
            throw .cursorPixelsMismatch
        }
        guard cursor.width <= maxCursorSide, cursor.height <= maxCursorSide else {
            throw .cursorTooLarge(width: cursor.width, height: cursor.height)
        }
        guard cursor.pixels.isEmpty || UInt64(cursor.pixels.count) == UInt64(cursor.width) * UInt64(cursor.height) * 4
        else {
            throw .cursorPixelsMismatch
        }
    }

    // MARK: Windows

    /// Decides whether a guest window may open. `existing` is the open windows of this environment.
    /// Returns the window's popup depth (0 for toplevels).
    public static func admitOpen(
        id: UInt32, isPopup: Bool, parent: UInt32, app: String, existing: [UInt32: WindowAccount]
    ) throws(Violation) -> Int {
        guard existing[id] == nil else { throw .duplicateWindow(id) }
        guard existing.count < maxWindowsTotal else { throw .tooManyWindows }
        guard existing.values.filter({ $0.app == app }).count < maxWindowsPerApp else { throw .tooManyWindows }
        guard isPopup else { return 0 }
        guard let owner = existing[parent] else { throw .unknownParent(parent) }
        guard owner.app == app else { throw .parentFromOtherApp(parent) }
        let depth = owner.popupDepth + 1
        guard depth <= maxPopupDepth else { throw .popupTooDeep(depth) }
        return depth
    }

    /// What the agent keeps about an open window to judge later ones.
    public struct WindowAccount: Equatable, Sendable {
        public var app: String
        public var popupDepth: Int

        public init(app: String, popupDepth: Int) {
            self.app = app
            self.popupDepth = popupDepth
        }
    }
}
