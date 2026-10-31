// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Compression
import IOSurface

/// One guest window (toplevel or popup) as a native macOS window.
@MainActor
final class GuestWindow: NSObject, NSWindowDelegate {
    typealias Opened = Crosswind_Display_WindowOpened
    typealias Frame = Crosswind_Display_Frame
    typealias DamageRect = Crosswind_Display_Rect

    let id: UInt32
    let kind: Crosswind_Display_WindowKind
    let view = SurfaceView(frame: .zero)
    private(set) var window: NSWindow?
    private var buffers: [IOSurface] = []
    private var frontIndex = 0
    private var previousDamage: [(x: UInt32, y: UInt32, width: UInt32, height: UInt32)] = []
    private var scale: CGFloat = 1
    private var popupOffset: CGPoint = .zero
    private weak var parent: GuestWindow?
    private var pendingAck: UInt64?
    private var displayLink: CADisplayLink?
    private var guestDrivenResize = false

    var send: ((ToGuest.OneOf_Msg) -> Void)?

    init(opened: Opened, parent: GuestWindow?) {
        id = opened.id
        kind = opened.kind
        self.parent = parent
        popupOffset = CGPoint(x: Int(opened.x), y: Int(opened.y))
        super.init()
        view.onInput = { [weak self] event in
            guard let self else { return }
            self.send?(
                .input(
                    .with {
                        $0.window = self.id
                        $0.event = event
                    }))
        }
    }

    func update(_ changed: Crosswind_Display_WindowChanged) {
        if changed.hasTitle { window?.title = changed.title }
    }

    // MARK: Frames

    func apply(_ frame: Frame, title: String) {
        // The guest is untrusted: refuse anything outside the limits before touching a surface.
        do {
            try DisplayLimits.checkFrame(frame)
        } catch {
            if DisplayLimits.violationLog.allow() { Log.display.warning("window \(self.id): frame refused: \(error)") }
            return
        }
        let scale = CGFloat(frame.scale120) / 120
        let width = Int(frame.width)
        let height = Int(frame.height)
        if buffers.isEmpty || buffers[0].width != width || buffers[0].height != height {
            buffers = (0..<2).compactMap { _ in
                IOSurface(properties: [
                    .width: width, .height: height, .bytesPerElement: 4, .pixelFormat: 0x4247_5241,  // 'BGRA'
                ])
            }
            previousDamage = []
        }
        guard buffers.count == 2 else { return }
        self.scale = scale

        // Core Animation only re-reads a layer's IOSurface when it is handed a different one, so frames alternate
        // between two surfaces. The back surface is one frame stale: carry over last frame's damage first.
        let front = buffers[frontIndex]
        let back = buffers[1 - frontIndex]
        front.lock(options: .readOnly, seed: nil)
        back.lock(options: [], seed: nil)
        let stride = back.bytesPerRow
        for rect in previousDamage {
            for row in Int(rect.y)..<Int(rect.y + rect.height) {
                let offset = row * stride + Int(rect.x) * 4
                memcpy(back.baseAddress + offset, front.baseAddress + offset, Int(rect.width) * 4)
            }
        }
        var applied: [(x: UInt32, y: UInt32, width: UInt32, height: UInt32)] = []
        for rect in frame.damage where Self.decode(rect, into: back.baseAddress, stride: stride) {
            applied.append((x: rect.x, y: rect.y, width: rect.width, height: rect.height))
        }
        back.unlock(options: [], seed: nil)
        front.unlock(options: .readOnly, seed: nil)
        previousDamage = applied
        frontIndex = 1 - frontIndex
        let surface = buffers[frontIndex]

        let logical = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        if window == nil {
            makeWindow(size: logical, title: title)
        } else if let window, window.contentView!.bounds.size != logical, !window.inLiveResize {
            guestDrivenResize = true
            window.setContentSize(logical)
            guestDrivenResize = false
        }
        view.show(surface, scale: scale)

        pendingAck = frame.seq
        startDisplayLink()
    }

    /// Copies one damage rect into the surface. Returns false (and draws nothing) if its pixels do not decode to
    /// exactly the rect's size.
    @discardableResult
    private static func decode(_ rect: DamageRect, into base: UnsafeMutableRawPointer, stride: Int) -> Bool {
        guard let packed = RectCodec.unpack(width: rect.width, height: rect.height, pixels: rect.pixels) else {
            if DisplayLimits.violationLog.allow() { Log.display.warning("damage rect refused: payload does not decode") }
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

    /// The guest is told a frame was presented on the next display refresh, which paces its rendering to the screen.
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = view.displayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        if let seq = pendingAck {
            send?(
                .ack(
                    .with {
                        $0.window = id
                        $0.seq = seq
                    }))
            pendingAck = nil
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    // MARK: Window

    private func makeWindow(size: NSSize, title: String) {
        let frame = NSRect(origin: .zero, size: size)
        let window: NSWindow
        if kind == .popup {
            let panel = NSPanel(
                contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu
            panel.hasShadow = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false
            window = panel
        } else {
            window = NSWindow(
                contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                defer: false)
            window.title = title
            window.tabbingMode = .disallowed
            window.collectionBehavior = [.fullScreenPrimary]
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = view
        window.acceptsMouseMovedEvents = true
        self.window = window

        if kind == .popup, let parentWindow = parent?.window {
            let content = parentWindow.contentLayoutRect
            let topLeft = parentWindow.convertToScreen(NSRect(x: content.minX, y: content.maxY, width: 0, height: 0))
                .origin
            window.setFrameOrigin(NSPoint(x: topLeft.x + popupOffset.x, y: topLeft.y - popupOffset.y - size.height))
            parentWindow.addChildWindow(window, ordered: .above)
            window.orderFront(nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        displayLink?.invalidate()
        displayLink = nil
        window?.delegate = nil
        window?.parent?.removeChildWindow(window!)
        window?.close()
        window = nil
    }

    // MARK: NSWindowDelegate

    private func configure() {
        guard kind == .toplevel, let window, !guestDrivenResize else { return }
        let size = window.contentView!.bounds.size
        send?(
            .configure(
                .with {
                    $0.window = id
                    $0.width = UInt32(size.width.rounded())
                    $0.height = UInt32(size.height.rounded())
                    $0.scale120 = UInt32((window.backingScaleFactor * 120).rounded())
                    $0.activated = window.isKeyWindow
                    $0.fullscreen = window.styleMask.contains(.fullScreen)
                    $0.maximized = window.isZoomed
                }))
    }

    func windowDidResize(_ notification: Notification) { configure() }
    func windowDidBecomeKey(_ notification: Notification) { configure() }
    func windowDidResignKey(_ notification: Notification) { configure() }
    func windowDidEnterFullScreen(_ notification: Notification) { configure() }
    func windowDidExitFullScreen(_ notification: Notification) { configure() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        send?(.close(.with { $0.window = id }))  // the client decides (it may ask to save first)
        return false
    }
}
