// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Places and sizes native windows for guest windows: position, restored frames, cascade, popups and size limits.
@MainActor
enum WindowPlacement {
    /// Where the next cascaded main window goes: the last placed main window's top-left. Nil until one is placed.
    private static var cascadeAnchor: NSPoint?

    /// Pushes size limits to a main window. A fixed-size window is not resizable and has no zoom button.
    static func apply(_ limits: WindowPolicy.SizeLimits, to window: NSWindow) {
        window.contentMinSize = limits.minSize
        window.contentMaxSize = limits.maxSize
        if limits.isFixed {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
        window.standardWindowButton(.zoomButton)?.isEnabled = !limits.isFixed
    }

    /// Popups hang off the parent's content top-left, then are kept inside the visible frame of the parent's screen.
    static func popup(
        _ window: NSWindow, size: NSSize, offset: CGPoint, parentWindow: NSWindow
    ) {
        let content = parentWindow.contentLayoutRect
        let anchor = parentWindow.convertToScreen(NSRect(x: content.minX, y: content.maxY, width: 0, height: 0)).origin
        guard let visible = (parentWindow.screen ?? NSScreen.main)?.visibleFrame else {
            window.setFrame(NSRect(origin: anchor, size: size), display: false)
            return
        }
        window.setFrame(
            WindowPolicy.popupFrame(size: size, anchor: anchor, offset: offset, visible: visible), display: false)
    }

    /// Main windows restore the frame saved under their autosave name, keeping the guest's size. Without a usable
    /// saved frame the first window is centred and later ones cascade from the last placed window.
    static func main(_ window: NSWindow, size: NSSize, autosaveName: String) {
        let restored = window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        let savedTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(size)
        if restored, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.setFrameTopLeftPoint(savedTopLeft)
        } else if let anchor = cascadeAnchor {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: anchor))
        } else {
            window.center()
        }
        cascadeAnchor = NSPoint(x: window.frame.minX, y: window.frame.maxY)
    }
}
