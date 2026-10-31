// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Turns guest window messages into native windows. One instance per app stub (it only sees its own windows).
@MainActor
public final class DisplayServer {
    private let send: (ToGuest) -> Void
    private var windows: [UInt32: GuestWindow] = [:]
    private var titles: [UInt32: String] = [:]

    /// Called after a frame has been applied (used by the diagnostics HUD and benchmarks).
    public var onFrame: ((_ window: UInt32, _ seq: UInt64, _ bytes: Int) -> Void)?
    public var windowIDs: [UInt32] { windows.keys.sorted() }

    public init(messages: AsyncStream<ToHost>, send: @escaping (ToGuest) -> Void) {
        self.send = send
        Task { [weak self] in
            for await message in messages { self?.handle(message) }
            self?.closeAll()
        }
    }

    /// Injects input as if it came from the window's view (tests and the control interface).
    public func inject(window: UInt32, _ event: Crosswind_Display_Input.OneOf_Event) {
        send(
            .with {
                $0.input = .with {
                    $0.window = window
                    $0.event = event
                }
            })
    }

    private func handle(_ message: ToHost) {
        switch message.msg {
        case .opened(let opened):
            let window = GuestWindow(opened: opened, parent: windows[opened.parent])
            window.send = { [send] msg in send(.with { $0.msg = msg }) }
            windows[opened.id] = window
            titles[opened.id] = opened.title
        case .changed(let changed):
            if changed.hasTitle { titles[changed.id] = changed.title }
            windows[changed.id]?.update(changed)
        case .closed(let closed):
            windows.removeValue(forKey: closed.id)?.close()
            titles.removeValue(forKey: closed.id)
        case .frame(let frame):
            windows[frame.window]?.apply(frame, title: titles[frame.window] ?? "")
            onFrame?(frame.window, frame.seq, frame.damage.reduce(0) { $0 + $1.pixels.count })
        case .cursor(let cursor):
            windows[cursor.window]?.view.setCursor(CursorMap.cursor(named: cursor.name))
        case nil:
            break
        }
    }

    private func closeAll() {
        for window in windows.values { window.close() }
        windows.removeAll()
    }
}
