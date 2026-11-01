// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Testing

@testable import CrosswindKit

@Test func unboundedSizeLimitsAreOpenEnded() {
    let limits = WindowPolicy.SizeLimits(minWidth: 0, minHeight: 0, maxWidth: 0, maxHeight: 0)
    #expect(limits.minSize == .zero)
    #expect(limits.maxSize.width == .greatestFiniteMagnitude)
    #expect(limits.maxSize.height == .greatestFiniteMagnitude)
    #expect(!limits.isFixed)
}

@Test func equalMinAndMaxIsFixedSize() {
    let dialog = WindowPolicy.SizeLimits(minWidth: 400, minHeight: 300, maxWidth: 400, maxHeight: 300)
    #expect(dialog.isFixed)
    #expect(dialog.maxSize == NSSize(width: 400, height: 300))
    // Only one axis fixed is still resizable.
    #expect(!WindowPolicy.SizeLimits(minWidth: 400, minHeight: 300, maxWidth: 400, maxHeight: 0).isFixed)
}

@Test func sizeLimitsAreClampedToSurfaceLimit() {
    let huge = WindowPolicy.SizeLimits(minWidth: .max, minHeight: 0, maxWidth: .max, maxHeight: 0)
    #expect(huge.minWidth == DisplayLimits.maxSurfaceSide)
    #expect(huge.maxWidth == DisplayLimits.maxSurfaceSide)
}

@Test func popupBelowParentWhenItFits() {
    let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let frame = WindowPolicy.popupFrame(
        size: NSSize(width: 200, height: 100), anchor: NSPoint(x: 300, y: 700), offset: CGPoint(x: 10, y: 5),
        visible: visible)
    #expect(frame == NSRect(x: 310, y: 595, width: 200, height: 100))
}

@Test func popupFlipsAboveParentWhenBelowIsOffScreen() {
    let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    let frame = WindowPolicy.popupFrame(
        size: NSSize(width: 200, height: 100), anchor: NSPoint(x: 300, y: 60), offset: CGPoint(x: 0, y: 0),
        visible: visible)
    #expect(frame.minY == 60)  // below would start at y = -40, so it sits above the parent's top edge
    #expect(frame.maxY <= visible.maxY)
}

@Test func popupClampedInsideVisibleFrame() {
    let visible = NSRect(x: 0, y: 25, width: 1000, height: 775)
    let rightEdge = WindowPolicy.popupFrame(
        size: NSSize(width: 200, height: 100), anchor: NSPoint(x: 950, y: 700), offset: CGPoint(x: 0, y: 0),
        visible: visible)
    #expect(rightEdge.maxX == visible.maxX)
    let bottomEdge = WindowPolicy.popupFrame(
        size: NSSize(width: 200, height: 100), anchor: NSPoint(x: 100, y: 60), offset: CGPoint(x: 0, y: 0),
        visible: visible)
    #expect(bottomEdge.minY >= visible.minY)
}

@Test func autosaveNameIsStableAndSafe() {
    #expect(WindowPolicy.autosaveName(appID: "org.gnome.Calculator", index: 0) == "org.gnome.calculator.0")
    #expect(WindowPolicy.autosaveName(appID: "a b/c", index: 2) == "a_b_c.2")
    #expect(WindowPolicy.autosaveName(appID: "", index: 1) == "window.1")
    #expect(WindowPolicy.autosaveName(appID: "app", index: -3) == "app.0")
}
