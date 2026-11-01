// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Display routing for `AgentCore`: guest windows, frames and cursors go to the stub of their app, after
/// `DisplayLimits` checks. Split out of AgentCore.swift to keep that file within the lint limits.
extension AgentCore {
    // MARK: Display

    func attach(display connection: DisplayConnection) {
        displayToGuest = connection
        connection.send(.with { $0.output = output() })
        Task { [weak self] in
            for await message in connection.messages { self?.route(display: message) }
            self?.guestDisplayEnded()
        }
    }

    /// Guest display messages: checked against `DisplayLimits` and cleaned (titles, identifiers) before they reach a
    /// stub. A refused message is logged (rate limited) and dropped; nothing is forwarded for it.
    func route(display message: ToHost) {
        switch message.msg {
        case .opened(var opened)?:
            opened.title = DisplayLimits.sanitize(opened.title, maxBytes: DisplayLimits.maxTitleBytes)
            opened.appID = DisplayLimits.sanitize(opened.appID, maxBytes: DisplayLimits.maxIdentifierBytes)
            opened.flatpakID = DisplayLimits.sanitize(opened.flatpakID, maxBytes: DisplayLimits.maxIdentifierBytes)
            opened.launchID = DisplayLimits.sanitize(opened.launchID, maxBytes: DisplayLimits.maxIdentifierBytes)
            let app = opened.flatpakID.isEmpty ? opened.appID : opened.flatpakID
            let accounts = windows.mapValues { DisplayLimits.WindowAccount(app: $0.app, popupDepth: $0.popupDepth) }
            do {
                let depth = try DisplayLimits.admitOpen(
                    id: opened.id, isPopup: opened.kind == .popup, parent: opened.parent, app: app, existing: accounts)
                windows[opened.id] = WindowRecord(app: app, title: opened.title, popupDepth: depth)
                send(.with { $0.msg = .opened(opened) }, toStubOf: app)
            } catch {
                refuse(error, "window \(opened.id)")
            }
        case .changed(var changed)?:
            guard windows[changed.id] != nil else { return }
            if changed.hasTitle {
                changed.title = DisplayLimits.sanitize(changed.title, maxBytes: DisplayLimits.maxTitleBytes)
                windows[changed.id]?.title = changed.title
            }
            send(.with { $0.msg = .changed(changed) }, toStubOfWindow: changed.id)
        case .closed(let closed)?:
            send(message, toStubOfWindow: closed.id)
            windows.removeValue(forKey: closed.id)
        case .frame(let frame)?:
            guard windows[frame.window] != nil else { return }
            do {
                try DisplayLimits.checkFrame(frame)
            } catch {
                return refuse(error, "frame for window \(frame.window)")
            }
            record(frame)
            send(message, toStubOfWindow: frame.window)
        case .cursor(let cursor)?:
            guard windows[cursor.window] != nil else { return }
            do {
                try DisplayLimits.checkCursor(cursor)
            } catch {
                return refuse(error, "cursor for window \(cursor.window)")
            }
            send(message, toStubOfWindow: cursor.window)
        case .textInputState(let state)?:
            guard windows[state.window] != nil else { return }
            send(message, toStubOfWindow: state.window)
        case nil:
            break
        }
    }

    /// Input and acknowledgements are host messages; this only keeps them well-formed for the guest.
    func validInput(_ input: ToGuest) -> Bool {
        switch input.msg {
        case .input(let value)?:
            if case .motion(let motion)? = value.event { return motion.x.isFinite && motion.y.isFinite }
            return true
        case .textInput(let text)?:
            // Composition results are small; a stub cannot push megabytes of text through the IME path.
            let bytes = text.commit.text.utf8.count + text.preedit.text.utf8.count
            return bytes <= TextInputState.maxBytes
        default:
            return true
        }
    }

    func refuse(_ error: Error, _ what: String) {
        guard DisplayLimits.violationLog.allow() else { return }
        Log.display.warning("guest \(what, privacy: .public) refused: \(String(describing: error), privacy: .public)")
    }

    func send(_ message: ToHost, toStubOfWindow window: UInt32) {
        guard let app = windows[window]?.app else { return }
        send(message, toStubOf: app)
    }

    func send(_ message: ToHost, toStubOf app: String) {
        stubs[app]?.connection.send(.with { $0.display = message })
    }

    func guestDisplayEnded() {
        displayToGuest = nil
        for (window, record) in windows {
            send(.with { $0.closed = .with { $0.id = window } }, toStubOf: record.app)
        }
        windows.removeAll()
    }

    func record(_ frame: Crosswind_Display_Frame) {
        guard var record = windows[frame.window] else { return }
        record.frames += 1
        record.width = frame.width
        record.height = frame.height
        record.scale120 = frame.scale120
        if let start = record.lastInput {
            let elapsed = ContinuousClock.now - start
            record.lastLatencyMs =
                Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3
            record.lastInput = nil
        }
        windows[frame.window] = record
    }

    func info() -> [Crosswind_Agent_WindowInfo] {
        windows.sorted { $0.key < $1.key }.map { id, record in
            .with {
                $0.id = id
                $0.appID = record.app
                $0.title = record.title
                $0.width = record.width
                $0.height = record.height
                $0.scale120 = record.scale120
                $0.frames = record.frames
                $0.lastInputToFrameMs = record.lastLatencyMs
            }
        }
    }

    /// Forwards input to the guest and starts the input-to-frame clock for the window.
    func send(_ input: ToGuest) {
        if case .input(let value)? = input.msg, windows[value.window] != nil {
            if case .leave? = value.event {} else { windows[value.window]?.lastInput = .now }
        }
        displayToGuest?.send(input)
    }

    func windowID(of input: ToGuest) -> UInt32 {
        switch input.msg {
        case .configure(let value)?: value.window
        case .ack(let value)?: value.window
        case .input(let value)?: value.window
        case .close(let value)?: value.window
        case .textInput(let value)?: value.window
        case .output?, .keyboardLayout?, nil: 0
        }
    }
}
