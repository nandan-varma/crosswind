// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Turns guest window messages into native windows. One instance per app stub (it only sees its own windows).
@MainActor
public final class DisplayServer {
    private let send: (ToGuest) -> Void
    private var windows: [UInt32: GuestWindow] = [:]
    private var titles: [UInt32: String] = [:]
    /// Main windows opened so far; numbers their saved frames.
    private var mainWindowsOpened = 0
    private var layoutObserver: KeyboardLayoutObserver?

    /// Called after a frame has been applied (used by the diagnostics HUD and benchmarks).
    public var onFrame: ((_ window: UInt32, _ seq: UInt64, _ bytes: Int) -> Void)?
    /// Makes files dropped from the Mac visible to the guest and returns their guest paths (set by the stub).
    public var resolveDroppedFiles: (([URL]) async -> [String])?
    public var windowIDs: [UInt32] { windows.keys.sorted() }

    public init(messages: AsyncStream<ToHost>, send: @escaping (ToGuest) -> Void) {
        self.send = send
        layoutObserver = KeyboardLayoutObserver { [send] layout in send(Self.keyboardLayoutMessage(layout)) }
        send(Self.keyboardLayoutMessage(layoutObserver?.current ?? .us))
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
            var index = 0
            if opened.kind == .toplevel {
                index = mainWindowsOpened
                mainWindowsOpened += 1
            }
            let window = GuestWindow(opened: opened, parent: windows[opened.parent], index: index)
            window.send = { [send] msg in send(.with { $0.msg = msg }) }
            let id = opened.id
            window.view.onTextInput = { [send] input in
                var message = input
                message.window = id
                send(.with { $0.msg = .textInput(message) })
            }
            window.onResignKey = { [weak self] in self?.dismissPopups(of: opened.id) }
            window.view.onDrag = { [weak self] event in self?.drag(event, window: opened.id) }
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
        case .textInputState(let state):
            windows[state.window]?.view.setTextInputEnabled(state.enabled)
        case .dragStarted(let drag):
            windows[drag.window]?.view.pendingDrag = pendingDrag(from: drag)
        case .dragStatus(let status):
            windows[status.window]?.view.dragAccepted = status.accepted
        case nil:
            break
        }
    }

    // MARK: Drag and drop

    /// A drag from a Mac app over one of this app's windows, as guest messages. Files are made visible to the guest
    /// first (`resolveDroppedFiles`), so the drop message carries guest paths.
    private func drag(_ event: DragEvent, window: UInt32) {
        switch event {
        case .enter(let point, let hasText, let hasFiles):
            send(
                .with {
                    $0.msg = .dragEnter(
                        .with {
                            $0.window = window
                            $0.x = point.x
                            $0.y = point.y
                            $0.offersText = hasText
                            $0.offersFiles = hasFiles
                        })
                })
        case .motion(let point):
            send(
                .with {
                    $0.msg = .dragMotion(
                        .with {
                            $0.window = window
                            $0.x = point.x
                            $0.y = point.y
                        })
                })
        case .leave:
            send(.with { $0.msg = .dragLeave(.with { $0.window = window }) })
        case .takeOver:
            send(.with { $0.msg = .dragCancel(.with { $0.window = window }) })
        case .drop(let text, let files):
            Task { [weak self] in
                guard let self else { return }
                let paths = files.isEmpty ? [] : await resolveDroppedFiles?(files) ?? []
                send(
                    .with {
                        $0.msg = .dragDrop(
                            .with {
                                $0.window = window
                                $0.text = text ?? ""
                                $0.paths = paths
                            })
                    })
            }
        }
    }

    /// The Mac side of a drag an app started: its text, and the files that lie inside a shared folder.
    private func pendingDrag(from drag: Crosswind_Display_DragStarted) -> PendingDrag? {
        let folders = (try? SharedFolders.load(from: SharedFolders.defaultFile)) ?? SharedFolders()
        let files = drag.uris.compactMap { uri -> URL? in
            guard let path = URL(string: uri)?.path, let host = folders.hostPath(forGuestPath: path) else { return nil }
            return URL(fileURLWithPath: host)
        }
        guard !drag.text.isEmpty || !files.isEmpty else { return nil }
        return PendingDrag(text: files.isEmpty ? drag.text : nil, files: files)
    }

    private static func keyboardLayoutMessage(_ layout: XkbLayout) -> ToGuest {
        .with {
            $0.msg = .keyboardLayout(
                .with {
                    $0.layout = layout.layout
                    $0.variant = layout.variant
                })
        }
    }

    /// A menu belongs to the window it was opened from: when that window loses focus the guest dismisses it.
    private func dismissPopups(of parent: UInt32) {
        for window in windows.values where window.kind == .popup && window.parentID == parent {
            window.requestDismiss()
        }
    }

    private func closeAll() {
        for window in windows.values { window.close() }
        windows.removeAll()
    }
}
