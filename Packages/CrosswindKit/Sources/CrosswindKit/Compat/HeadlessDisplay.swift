// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Consumes a stub's display stream without any Mac window: each window's latest pixels and counters.
public actor HeadlessDisplay {
    public struct Window: Sendable {
        public let id: UInt32
        public let kind: Crosswind_Display_WindowKind
        public var title = ""
        public var canvas = Canvas()
        public var frames = 0
        public var scale120: UInt32 = 120
        public var closed = false
    }

    private var windows: [UInt32: Window] = [:]
    private var order: [UInt32] = []
    /// Frames received for all windows. Input that changes the picture raises it.
    public private(set) var frameCount = 0

    public init() {}

    /// The first toplevel the guest opened, if any.
    public var toplevel: Window? {
        order.lazy.compactMap { self.windows[$0] }.first { $0.kind == .toplevel }
    }

    /// The open toplevel with the most frames: the window a screenshot shows.
    public var primary: Window? {
        order.lazy.compactMap { self.windows[$0] }.filter { $0.kind == .toplevel && !$0.closed }
            .max { $0.frames < $1.frames }
    }

    /// Applies one message. Returns the reply the guest waits for before its next frame (an ack), if any.
    public func consume(_ message: ToHost) -> ToGuest? {
        switch message.msg {
        case .opened(let opened)?:
            windows[opened.id] = Window(id: opened.id, kind: opened.kind, title: opened.title)
            order.append(opened.id)
        case .changed(let changed)?:
            if changed.hasTitle { windows[changed.id]?.title = changed.title }
        case .closed(let closed)?:
            windows[closed.id]?.closed = true
        case .frame(let frame)?:
            guard var window = windows[frame.window] else { return nil }
            window.canvas.apply(frame)
            window.frames += 1
            window.scale120 = frame.scale120
            windows[frame.window] = window
            frameCount += 1
            return .with {
                $0.msg = .ack(
                    .with {
                        $0.window = frame.window
                        $0.seq = frame.seq
                    })
            }
        case .cursor?, .textInputState?, nil:
            break
        }
        return nil
    }
}
