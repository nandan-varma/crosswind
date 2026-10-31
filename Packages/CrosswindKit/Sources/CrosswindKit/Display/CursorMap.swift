// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// CSS/xcursor shape names (what `wp_cursor_shape_v1` and cursor themes use) to system cursors.
@MainActor
enum CursorMap {
    static func cursor(named name: String) -> NSCursor? {
        switch name {
        case "": nil
        case "text", "vertical-text": .iBeam
        case "pointer", "hand", "hand1", "hand2": .pointingHand
        case "crosshair", "cross", "cell": .crosshair
        case "grab", "openhand": .openHand
        case "grabbing", "closedhand", "move", "all-scroll": .closedHand
        case "not-allowed", "no-drop", "crossed_circle": .operationNotAllowed
        case "context-menu": .contextualMenu
        case "ew-resize", "e-resize", "w-resize", "col-resize", "sb_h_double_arrow": .resizeLeftRight
        case "ns-resize", "n-resize", "s-resize", "row-resize", "sb_v_double_arrow": .resizeUpDown
        case "nesw-resize", "ne-resize", "sw-resize": .frameResize(position: .topRight, directions: .all)
        case "nwse-resize", "nw-resize", "se-resize": .frameResize(position: .topLeft, directions: .all)
        case "zoom-in": .zoomIn
        case "zoom-out": .zoomOut
        default: .arrow
        }
    }
}
