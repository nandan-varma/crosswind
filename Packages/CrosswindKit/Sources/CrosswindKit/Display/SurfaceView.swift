// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import IOSurface

typealias InputEvent = Crosswind_Display_Input.OneOf_Event

/// Shows one guest surface (an IOSurface updated in place) and turns AppKit events into guest input.
@MainActor
final class SurfaceView: NSView {
    var onInput: ((InputEvent) -> Void)?
    var commandActsAsControl = true
    private(set) var cursor: NSCursor? = .arrow

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .topLeft
        layer?.isOpaque = false
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ surface: IOSurface, scale: CGFloat) {
        layer?.contentsScale = scale
        // Assigning the surface again is what makes Core Animation pick up in-place changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = surface
        CATransaction.commit()
    }

    func setCursor(_ cursor: NSCursor?) {
        self.cursor = cursor
        window?.invalidateCursorRects(for: self)
        (cursor ?? NSCursor.arrow).set()
    }

    override func resetCursorRects() {
        if let cursor { addCursorRect(bounds, cursor: cursor) }
    }

    // MARK: Pointer

    private func ms(_ event: NSEvent) -> UInt32 { UInt32(truncatingIfNeeded: Int(event.timestamp * 1000)) }

    private func motion(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onInput?(
            .motion(
                .with {
                    $0.x = p.x
                    $0.y = p.y
                    $0.timeMs = ms(event)
                }))
    }

    override func mouseMoved(with event: NSEvent) { motion(event) }
    override func mouseDragged(with event: NSEvent) { motion(event) }
    override func rightMouseDragged(with event: NSEvent) { motion(event) }
    override func otherMouseDragged(with event: NSEvent) { motion(event) }
    override func mouseEntered(with event: NSEvent) { motion(event) }
    override func mouseExited(with event: NSEvent) { onInput?(.leave(.init())) }

    private func button(_ event: NSEvent, _ code: UInt32, pressed: Bool) {
        motion(event)
        onInput?(
            .button(
                .with {
                    $0.button = code
                    $0.pressed = pressed
                    $0.timeMs = ms(event)
                }))
    }

    override func mouseDown(with event: NSEvent) { button(event, 0x110, pressed: true) }
    override func mouseUp(with event: NSEvent) { button(event, 0x110, pressed: false) }
    override func rightMouseDown(with event: NSEvent) { button(event, 0x111, pressed: true) }
    override func rightMouseUp(with event: NSEvent) { button(event, 0x111, pressed: false) }
    override func otherMouseDown(with event: NSEvent) { button(event, 0x112, pressed: true) }
    override func otherMouseUp(with event: NSEvent) { button(event, 0x112, pressed: false) }

    override func scrollWheel(with event: NSEvent) {
        // Wayland axis: positive is down/right; AppKit's natural-scroll delta is the opposite sign.
        let precise = event.hasPreciseScrollingDeltas
        let factor: CGFloat = precise ? 1 : 10
        let ended =
            event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
        onInput?(
            .axis(
                .with {
                    $0.dx = -event.scrollingDeltaX * factor
                    $0.dy = -event.scrollingDeltaY * factor
                    $0.finished = ended
                    $0.timeMs = ms(event)
                }))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }  // clients repeat keys themselves from wl_keyboard.repeat_info
        key(event.keyCode, pressed: true, time: ms(event))
    }

    override func keyUp(with event: NSEvent) { key(event.keyCode, pressed: false, time: ms(event)) }

    override func flagsChanged(with event: NSEvent) {
        let code = event.keyCode
        if code == 57 {  // caps lock reports only toggles
            key(code, pressed: true, time: ms(event))
            key(code, pressed: false, time: ms(event))
        } else if let mask = KeyMap.modifierMask(forMacKeyCode: code) {
            key(code, pressed: event.modifierFlags.rawValue & mask != 0, time: ms(event))
        }
    }

    private func key(_ macCode: UInt16, pressed: Bool, time: UInt32) {
        var evdev = KeyMap.evdev(forMacKeyCode: macCode)
        if commandActsAsControl {
            if macCode == 55 { evdev = UInt32(KeyMap.leftControl) }
            if macCode == 54 { evdev = UInt32(KeyMap.rightControl) }
        }
        guard let evdev else { return }
        onInput?(
            .key(
                .with {
                    $0.keycode = evdev
                    $0.pressed = pressed
                    $0.timeMs = time
                }))
    }
}
