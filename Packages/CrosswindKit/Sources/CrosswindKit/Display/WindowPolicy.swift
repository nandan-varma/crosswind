// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Pure window-placement and sizing rules for guest windows. No AppKit window state is touched here, so the rules
/// can be unit-tested.
public enum WindowPolicy {
    /// Content size limits in logical points. A 0 in the guest's message means unbounded.
    public struct SizeLimits: Equatable {
        /// Wire values, clamped to the surface limit. 0 means unbounded for the maximum.
        public let minWidth: UInt32
        public let minHeight: UInt32
        public let maxWidth: UInt32
        public let maxHeight: UInt32

        public init(minWidth: UInt32, minHeight: UInt32, maxWidth: UInt32, maxHeight: UInt32) {
            self.minWidth = min(minWidth, DisplayLimits.maxSurfaceSide)
            self.minHeight = min(minHeight, DisplayLimits.maxSurfaceSide)
            self.maxWidth = min(maxWidth, DisplayLimits.maxSurfaceSide)
            self.maxHeight = min(maxHeight, DisplayLimits.maxSurfaceSide)
        }

        public var minSize: NSSize { NSSize(width: CGFloat(minWidth), height: CGFloat(minHeight)) }

        public var maxSize: NSSize {
            NSSize(
                width: maxWidth == 0 ? .greatestFiniteMagnitude : CGFloat(maxWidth),
                height: maxHeight == 0 ? .greatestFiniteMagnitude : CGFloat(maxHeight))
        }

        /// A dialog with min == max: no resizing and no zoom.
        public var isFixed: Bool { minWidth > 0 && minWidth == maxWidth && minHeight > 0 && minHeight == maxHeight }
    }

    /// Places a popup of `size` at `offset` from `anchor` (the parent's content top-left, screen coordinates).
    /// It goes below the anchor, flips above when it does not fit below, and is clamped into `visible`.
    public static func popupFrame(size: NSSize, anchor: NSPoint, offset: CGPoint, visible: NSRect) -> NSRect {
        var y = anchor.y - offset.y - size.height  // below the parent's content top
        if y < visible.minY {
            let flipped = anchor.y + offset.y  // above the parent's content top
            if flipped + size.height <= visible.maxY { y = flipped }
        }
        var x = anchor.x + offset.x
        x = clamp(x, length: size.width, in: visible.minX...visible.maxX)
        y = clamp(y, length: size.height, in: visible.minY...visible.maxY)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    /// Keeps a span of `length` inside `bounds`, preferring the lower edge when it does not fit.
    static func clamp(_ origin: CGFloat, length: CGFloat, in bounds: ClosedRange<CGFloat>) -> CGFloat {
        if length >= bounds.upperBound - bounds.lowerBound { return bounds.lowerBound }
        return min(max(origin, bounds.lowerBound), bounds.upperBound - length)
    }

    /// The autosave name that remembers a main window's frame: `<appid>.<index>`. The index counts the app's main
    /// windows in opening order. Characters outside `[a-z0-9._-]` are replaced so the key stays a plain defaults key.
    public static func autosaveName(appID: String, index: Int) -> String {
        let base = appID.lowercased().map {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") ? $0 : "_"
        }
        let id = base.isEmpty ? "window" : String(base.prefix(DisplayLimits.maxIdentifierBytes))
        return "\(id).\(max(index, 0))"
    }
}
