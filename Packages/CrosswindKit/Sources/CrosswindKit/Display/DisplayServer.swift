// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Terminates the display channel: turns guest window messages into native windows.
@MainActor
public final class DisplayServer {
    private let connection: FramedConnection
    private var windows: [UInt32: GuestWindow] = [:]
    private var titles: [UInt32: String] = [:]

    public init(connection: FramedConnection) {
        self.connection = connection
        sendOutput()
        Task { [weak self] in
            guard let messages = self?.connection.messages else { return }
            for await message in messages { self?.handle(message) }
            self?.closeAll()
        }
    }

    private func sendOutput() {
        let screen = NSScreen.main
        let size = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        connection.send(.with {
            $0.output = .with {
                $0.width = UInt32(size.width)
                $0.height = UInt32(size.height)
                $0.scale120 = UInt32(((screen?.backingScaleFactor ?? 2) * 120).rounded())
                $0.refreshMhz = UInt32((screen?.maximumFramesPerSecond ?? 60) * 1000)
            }
        })
    }

    private func handle(_ message: ToHost) {
        switch message.msg {
        case .opened(let opened):
            let window = GuestWindow(opened: opened, parent: windows[opened.parent])
            window.send = { [connection] msg in connection.send(.with { $0.msg = msg }) }
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
