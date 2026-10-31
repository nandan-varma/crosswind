// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Compression
import IOSurface

/// One guest window (toplevel or popup) as a native macOS window.
@MainActor
final class GuestWindow: NSObject, NSWindowDelegate {
    typealias Opened = Crosswind_Display_WindowOpened
    typealias Frame = Crosswind_Display_Frame

    let id: UInt32
    let kind: Crosswind_Display_WindowKind
    let view = SurfaceView(frame: .zero)
    private(set) var window: NSWindow?
    private var surface: IOSurface?
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
            self.send?(.input(.with { $0.window = self.id; $0.event = event }))
        }
    }

    func update(_ changed: Crosswind_Display_WindowChanged) {
        if changed.hasTitle { window?.title = changed.title }
    }

    // MARK: Frames

    func apply(_ frame: Frame, title: String) {
        let scale = CGFloat(frame.scale120) / 120
        let width = Int(frame.width), height = Int(frame.height)
        if surface == nil || surface!.width != width || surface!.height != height {
            surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4, .pixelFormat: 0x4247_5241,  // 'BGRA'
            ])
        }
        guard let surface else { return }
        self.scale = scale

        surface.lock(options: [], seed: nil)
        let base = surface.baseAddress, stride = surface.bytesPerRow
        for rect in frame.damage {
            Self.decode(rect, into: base, stride: stride)
        }
        surface.unlock(options: [], seed: nil)

        let logical = NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        if window == nil { makeWindow(size: logical, title: title) }
        else if let window, window.contentView!.bounds.size != logical, !window.inLiveResize {
            guestDrivenResize = true
            window.setContentSize(logical)
            guestDrivenResize = false
        }
        view.show(surface, scale: scale)

        pendingAck = frame.seq
        startDisplayLink()
    }

    private static func decode(_ rect: Crosswind_Display_Rect, into base: UnsafeMutableRawPointer, stride: Int) {
        let w = Int(rect.width), h = Int(rect.height)
        let packed = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { packed.deallocate() }
        let n = rect.pixels.withUnsafeBytes {
            compression_decode_buffer(packed, w * h * 4, $0.bindMemory(to: UInt8.self).baseAddress!, $0.count, nil, COMPRESSION_LZ4_RAW)
        }
        guard n == w * h * 4 else { return }
        for row in 0..<h {
            memcpy(base + (Int(rect.y) + row) * stride + Int(rect.x) * 4, packed + row * w * 4, w * 4)
        }
    }

    /// The guest is told a frame was presented on the next display refresh, which paces its rendering to the screen.
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = view.displayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        if let seq = pendingAck {
            send?(.ack(.with { $0.window = id; $0.seq = seq }))
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
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu
            panel.hasShadow = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false
            window = panel
        } else {
            window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
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
            let topLeft = parentWindow.convertToScreen(NSRect(x: content.minX, y: content.maxY, width: 0, height: 0)).origin
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
        send?(.configure(.with {
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
