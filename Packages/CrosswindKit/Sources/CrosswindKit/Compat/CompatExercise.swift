// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension CompatHarness {
    /// Launches the app through a stub and runs the checks. A failed step records its result and ends the run,
    /// except for input, which only reports `unknown` when nothing reacts.
    static func exercise(_ appID: String, report: inout Report, session: Session) async throws {
        let stub = try await AgentClient.connect(role: .stub, appID: appID)
        let display = HeadlessDisplay()
        let pump = Task {
            for await message in stub.display {
                if let reply = await display.consume(message) { await stub.send(display: reply) }
            }
        }
        defer {
            pump.cancel()
            Task { await stub.disconnect() }
        }

        do {
            _ = try await stub.command(.launchApp(.with { $0.appID = appID }))
        } catch {
            report.notes.append("launch failed: \(error)")
            report.checks.windowAppears = .fail
            return
        }
        let timeout = session.options.timeout
        let opened = await poll(timeout) { await display.toplevel != nil }
        report.checks.noCrash = await session.events.exitCode(appID) == nil ? .pass : .fail
        guard opened, let window = await display.toplevel else {
            report.checks.windowAppears = .fail
            report.notes.append("no window within \(timeout)")
            return
        }
        report.checks.windowAppears = .pass
        session.log("   window \(window.id) \(window.title)")

        await stub.send(display: configure(window.id))
        guard await checkRender(&report, display: display, timeout: timeout, appID: appID, session: session) else {
            return
        }
        await checkInput(&report, stub: stub, display: display, window: window.id, session: session)

        if await session.events.exitCode(appID) != nil {
            report.checks.noCrash = .fail
            report.notes.append("exited before close")
            return
        }
        await checkExit(&report, stub: stub, window: window.id, appID: appID, session: session)
    }

    /// Waits for a first frame, then checks the settled picture is not one flat colour and saves a screenshot.
    /// Returns false when there is no frame to continue with.
    private static func checkRender(
        _ report: inout Report, display: HeadlessDisplay, timeout: Duration, appID: String, session: Session
    ) async -> Bool {
        let rendered = await poll(timeout) { ((await display.primary)?.frames ?? 0) > 0 }
        guard rendered, await display.primary != nil else {
            report.checks.renders = .fail
            report.notes.append("no frame within \(timeout)")
            return false
        }
        try? await Task.sleep(for: .milliseconds(1500))
        guard let settled = await display.primary else { return false }
        let flat = settled.canvas.isFlat
        report.checks.renders = flat ? .fail : .pass
        if flat { report.notes.append("window is one flat colour") }
        let png = session.options.screenshotDirectory.appending(path: "\(appID).png")
        try? settled.canvas.writePNG(to: png)
        report.screenshot = "screenshots/\(appID).png"
        return true
    }

    /// Sends pointer motion, a click, Space and Return. `unknown` means no frame followed within 2 seconds.
    private static func checkInput(
        _ report: inout Report, stub: AgentClient, display: HeadlessDisplay, window: UInt32, session: Session
    ) async {
        guard let shot = await display.primary else { return }
        let before = await display.frameCount
        let width = Double(shot.canvas.width) * 120 / Double(shot.scale120)
        let height = Double(shot.canvas.height) * 120 / Double(shot.scale120)
        for event in inputSequence(window: window, x: width / 2, y: height / 2) {
            await stub.send(display: event)
            try? await Task.sleep(for: .milliseconds(60))
        }
        let reacted = await poll(.seconds(2)) { await display.frameCount > before }
        report.checks.inputWorks = reacted ? .pass : .unknown
    }

    /// Asks the window to close and expects the process to exit within 10 s. Otherwise the agent stops it,
    /// and the exit code shows whether it needed a signal.
    private static func checkExit(
        _ report: inout Report, stub: AgentClient, window: UInt32, appID: String, session: Session
    ) async {
        let events = session.events
        await stub.send(display: close(window))
        if await poll(.seconds(10), { await events.exitCode(appID) != nil }) {
            report.checks.cleanExit = .pass
            return
        }
        report.checks.cleanExit = .fail
        report.notes.append("did not exit within 10 s of a close request; stopping it")
        try? await session.control.control.stop(appID: appID)
        _ = await poll(.seconds(10)) { await events.exitCode(appID) != nil }
        switch await events.exitCode(appID) {
        case 137?: report.notes.append("needed SIGKILL (exit 137)")
        case 143?: report.notes.append("needed SIGTERM (exit 143)")
        case let code?: report.notes.append("exit code \(code) after stop")
        case nil: report.notes.append("still running after stop")
        }
    }

    private static func configure(_ window: UInt32) -> ToGuest {
        .with {
            $0.msg = .configure(
                .with {
                    $0.window = window
                    $0.width = 1024
                    $0.height = 768
                    $0.scale120 = 240
                    $0.activated = true
                })
        }
    }

    private static func close(_ window: UInt32) -> ToGuest {
        .with { $0.msg = .close(.with { $0.window = window }) }
    }

    /// Pointer motion to the centre, a left click, then Shift.
    private static func inputSequence(window: UInt32, x: Double, y: Double) -> [ToGuest] {
        func input(_ event: Crosswind_Display_Input.OneOf_Event) -> ToGuest {
            .with {
                $0.msg = .input(
                    .with {
                        $0.window = window
                        $0.event = event
                    })
            }
        }
        func key(_ code: UInt32, _ pressed: Bool) -> ToGuest {
            input(
                .key(
                    .with {
                        $0.keycode = code
                        $0.pressed = pressed
                    }))
        }
        return [
            input(
                .motion(
                    .with {
                        $0.x = x
                        $0.y = y
                    })),
            input(
                .button(
                    .with {
                        $0.button = 0x110
                        $0.pressed = true
                    })),
            input(
                .button(
                    .with {
                        $0.button = 0x110
                        $0.pressed = false
                    })),
            // Shift only: a harmless key. Space or Return would type into a document and make it
            // unsaved, so the close prompt would then be the app's correct behaviour, not a failure.
            key(42, true), key(42, false),  // Left Shift
        ]
    }
}
