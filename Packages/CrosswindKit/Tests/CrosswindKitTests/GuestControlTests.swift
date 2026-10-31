// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import CrosswindKit

@Suite struct GuestControlTests {
    @Test func outOfOrderResponsesReachTheirCallers() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        async let apps = control.installed()
        async let running = control.running()
        // Requests may arrive in either order; answer whichever is which, and the later one first.
        var requests: [Crosswind_Control_Request] = []
        requests.append(try #require(await guest.nextRequest()))
        requests.append(try #require(await guest.nextRequest()))
        var installed = Crosswind_Control_InstalledList()
        installed.apps = [Crosswind_Control_InstalledApp.with { $0.appID = "org.gnome.Calculator" }]
        var runningList = Crosswind_Control_RunningList()
        runningList.apps = [
            Crosswind_Control_RunningApp.with {
                $0.appID = "org.gnome.Calendar"
                $0.pid = 42
            }
        ]
        for request in requests.reversed() {
            if case .listRunning? = request.body {
                await guest.reply(to: request, .running(runningList))
            } else {
                await guest.reply(to: request, .installed(installed))
            }
        }

        #expect(try await apps.map(\.appID) == ["org.gnome.Calculator"])
        #expect(try await running.map(\.pid) == [42])
    }

    @Test func remoteErrorsAreMappedToGuestControlError() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let call = Task { try await control.stop(appID: "org.example.App") }
        await guest.reply(
            to: try #require(await guest.nextRequest()),
            .error(Crosswind_Control_Error.with { $0.message = "not running" }))

        await #expect(throws: GuestControlError.remote("not running")) { try await call.value }
    }

    @Test func disconnectFailsPendingAndLaterRequests() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let pending = Task { try await control.shutdown() }
        _ = try #require(await guest.nextRequest())
        await guest.disconnect()

        await #expect(throws: GuestControlError.disconnected) { try await pending.value }
        await #expect(throws: GuestControlError.disconnected) { try await control.running() }
    }

    @Test func installReportsProgressAndCompletes() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let install = Task { try await control.install(appID: "org.gnome.Calculator") }
        let request = try #require(await guest.nextRequest())
        await guest.reply(to: request, .operation(Crosswind_Control_Operation.with { $0.id = 7 }))
        let handle = try await install.value
        #expect(handle.id == 7)

        let result = Task { try await handle.result() }
        await guest.send(
            .event(
                .progress(
                    Crosswind_Control_Progress.with {
                        $0.operation = 7
                        $0.percent = 50
                    })))
        await guest.send(
            .event(
                .progress(
                    Crosswind_Control_Progress.with {
                        $0.operation = 7
                        $0.percent = 100
                    })))
        await guest.send(.event(.operationDone(Crosswind_Control_OperationDone.with { $0.operation = 7 })))

        var percents: [UInt32] = []
        for await progress in handle.progress { percents.append(progress.percent) }
        #expect(percents == [50, 100])
        try await result.value
    }

    @Test func operationErrorFailsResult() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let uninstall = Task { try await control.uninstall(appID: "org.example.App") }
        await guest.reply(
            to: try #require(await guest.nextRequest()), .operation(Crosswind_Control_Operation.with { $0.id = 3 }))
        let handle = try await uninstall.value

        await guest.send(
            .event(
                .operationDone(
                    Crosswind_Control_OperationDone.with {
                        $0.operation = 3
                        $0.error = Crosswind_Control_Error.with { $0.message = "flatpak failed" }
                    })))

        await #expect(throws: GuestControlError.remote("flatpak failed")) { try await handle.result() }
    }

    @Test func cancellationSendsCancelAndFailsResultWithCancelled() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let update = Task { try await control.update() }
        await guest.reply(
            to: try #require(await guest.nextRequest()), .operation(Crosswind_Control_Operation.with { $0.id = 9 }))
        let handle = try await update.value

        let result = Task { try await handle.result() }
        let cancel = Task { try await handle.cancel() }
        let cancelRequest = try #require(await guest.nextRequest())
        #expect(cancelRequest.cancelledOperation == 9)
        await guest.reply(to: cancelRequest, .ok(Crosswind_Control_Ok()))
        try await cancel.value

        await guest.send(
            .event(
                .operationDone(
                    Crosswind_Control_OperationDone.with {
                        $0.operation = 9
                        $0.cancelled = true
                    })))

        await #expect(throws: GuestControlError.cancelled) { try await result.value }
    }

    @Test func disconnectFailsOperationResult() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let install = Task { try await control.install(appID: "org.example.App") }
        await guest.reply(
            to: try #require(await guest.nextRequest()), .operation(Crosswind_Control_Operation.with { $0.id = 4 }))
        let handle = try await install.value

        let result = Task { try await handle.result() }
        await guest.disconnect()

        await #expect(throws: GuestControlError.disconnected) { try await result.value }
    }

    @Test func eventsExcludeProgressAndOperationDone() async throws {
        let guest = FakeGuest()
        let control = GuestControl(connection: guest.host)

        let install = Task { try await control.install(appID: "org.example.App") }
        await guest.reply(
            to: try #require(await guest.nextRequest()), .operation(Crosswind_Control_Operation.with { $0.id = 5 }))
        _ = try await install.value

        await guest.send(.event(.log(Crosswind_Control_LogLine.with { $0.text = "start" })))
        await guest.send(.event(.progress(Crosswind_Control_Progress.with { $0.operation = 5 })))
        await guest.send(.event(.operationDone(Crosswind_Control_OperationDone.with { $0.operation = 5 })))
        await guest.send(
            .event(
                .appStarted(
                    Crosswind_Control_AppStarted.with {
                        $0.appID = "a"
                        $0.pid = 1
                    })))
        await guest.send(
            .event(
                .appExited(
                    Crosswind_Control_AppExited.with {
                        $0.appID = "a"
                        $0.exitCode = 3
                    })))

        var received: [GuestControl.Event] = []
        for await event in control.events.prefix(3) { received.append(event) }
        guard received.count == 3,
            case .log(let line) = received[0],
            case .appStarted(let started) = received[1],
            case .appExited(let exited) = received[2]
        else {
            Issue.record("unexpected events: \(received)")
            return
        }
        #expect(line.text == "start")
        #expect(started.pid == 1)
        #expect(exited.exitCode == 3)
    }
}
