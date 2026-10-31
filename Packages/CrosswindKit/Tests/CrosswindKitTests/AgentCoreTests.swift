// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import CrosswindKit

@MainActor
@Suite struct AgentCoreTests {
    private func stopRequest(id: UInt64, appID: String) -> Crosswind_Control_Request {
        .with {
            $0.id = id
            $0.body = .stop(.with { $0.appID = appID })
        }
    }

    private func listRunningRequest(id: UInt64) -> Crosswind_Control_Request {
        .with {
            $0.id = id
            $0.body = .listRunning(Crosswind_Control_ListRunning())
        }
    }

    // MARK: Guest control

    @Test func clientRequestsReturnToTheirOwnClientWithOriginalIDs() async throws {
        let harness = AgentHarness()
        let guest = harness.attachGuest()
        let alice = harness.connect(.ctl)
        let bob = harness.connect(.ctl)

        // Both clients use request id 1; the guest must see two distinct ids.
        alice.send(request: stopRequest(id: 1, appID: "org.example.A"))
        bob.send(request: stopRequest(id: 1, appID: "org.example.B"))

        var guestIDs: [UInt64] = []
        for _ in 0..<2 {
            let request = try #require(await within { await guest.nextRequest() })
            guard case .stop(let stop)? = request.body else {
                Issue.record("expected a stop request, got \(String(describing: request.body))")
                return
            }
            guestIDs.append(request.id)
            guest.reply(to: request, .error(.with { $0.message = "stopped \(stop.appID)" }))
        }
        #expect(Set(guestIDs).count == 2)

        let aliceReply = try #require(await alice.inbox.first { $0.guestResponse != nil }?.guestResponse)
        #expect(aliceReply.id == 1)
        #expect(aliceReply.errorMessage == "stopped org.example.A")

        let bobReply = try #require(await bob.inbox.first { $0.guestResponse != nil }?.guestResponse)
        #expect(bobReply.id == 1)
        #expect(bobReply.errorMessage == "stopped org.example.B")
    }

    // MARK: Guest events

    @Test func guestEventsReachEveryClientAndUpdateRunningApps() async throws {
        let harness = AgentHarness()
        let guest = harness.attachGuest()
        let clients = [harness.connect(.store), harness.connect(.stub, appID: "org.example.A")]

        guest.send(
            .event(
                .appStarted(
                    .with {
                        $0.appID = "org.example.A"
                        $0.pid = 10
                    })))
        for client in clients {
            // The state update precedes the event it reflects.
            let state = await client.inbox.first { $0.stateUpdate?.runningApps == ["org.example.A"] }
            #expect(state != nil)
            let started = await client.inbox.first { message in
                if case .appStarted? = message.guestEvent { return true }
                return false
            }
            #expect(started != nil)
        }
        #expect(harness.session.state.runningApps == ["org.example.A"])

        guest.send(
            .event(
                .appExited(
                    .with {
                        $0.appID = "org.example.A"
                        $0.exitCode = 0
                    })))
        for client in clients {
            #expect(await client.inbox.first { $0.stateUpdate?.runningApps == [] } != nil)
        }
        #expect(harness.session.state.runningApps.isEmpty)
    }

    // MARK: Display routing

    @Test func windowsRouteToTheStubOfTheirFlatpakApp() async throws {
        let harness = AgentHarness()
        let display = await harness.attachDisplay()
        let stubA = harness.connect(.stub, appID: "org.example.A")
        let stubB = harness.connect(.stub, appID: "org.example.B")

        display.send(.opened(1, flatpakID: "org.example.A"))
        display.send(.frame(1))
        display.send(.changed(1, title: "Editor"))
        display.send(.closed(1))
        display.send(.opened(2, flatpakID: "org.example.B"))
        display.send(.opened(3, flatpakID: "org.example.A"))
        display.send(.opened(4, flatpakID: "org.example.B"))

        // Each stub's stream is ordered, so an exact sequence proves no foreign message was delivered.
        var seenByA: [ToHost] = []
        for _ in 0..<5 {
            seenByA.append(try #require(await stubA.nextDisplay()))
        }
        #expect(
            seenByA == [
                ToHost.opened(1, flatpakID: "org.example.A"),
                ToHost.frame(1),
                ToHost.changed(1, title: "Editor"),
                ToHost.closed(1),
                ToHost.opened(3, flatpakID: "org.example.A"),
            ])

        var seenByB: [ToHost] = []
        for _ in 0..<2 {
            seenByB.append(try #require(await stubB.nextDisplay()))
        }
        #expect(
            seenByB == [
                ToHost.opened(2, flatpakID: "org.example.B"),
                ToHost.opened(4, flatpakID: "org.example.B"),
            ])
    }

    @Test func windowWithoutFlatpakIDRoutesByAppID() async throws {
        let harness = AgentHarness()
        let display = await harness.attachDisplay()
        let stub = harness.connect(.stub, appID: "org.example.C")

        display.send(.opened(5, flatpakID: "", appID: "org.example.C"))
        display.send(.frame(5))
        #expect(await stub.nextDisplay() == ToHost.opened(5, appID: "org.example.C"))
        #expect(await stub.nextDisplay() == ToHost.frame(5))
    }

    @Test func inputIsForwardedOnlyForTheStubsOwnWindows() async throws {
        let harness = AgentHarness()
        let display = await harness.attachDisplay()
        let stubA = harness.connect(.stub, appID: "org.example.A")
        let stubB = harness.connect(.stub, appID: "org.example.B")
        let store = harness.connect(.store)

        display.send(.opened(1, flatpakID: "org.example.A"))
        display.send(.opened(2, flatpakID: "org.example.B"))
        #expect(await stubA.nextDisplay() == ToHost.opened(1, flatpakID: "org.example.A"))
        #expect(await stubB.nextDisplay() == ToHost.opened(2, flatpakID: "org.example.B"))

        // A's messages for B's window are dropped. Its input for its own window is the first thing the guest sees.
        stubA.send(display: .configure(2))
        stubA.send(display: .ack(2))
        stubA.send(display: .closeRequest(2))
        stubA.send(display: .input(1))
        #expect(await display.next() == ToGuest.input(1))

        // B's input for A's window is dropped; its own window is forwarded.
        stubB.send(display: .input(1))
        stubB.send(display: .input(2))
        #expect(await display.next() == ToGuest.input(2))

        // The store is not a stub: its display message is ignored. Its getState reply proves the message was handled.
        store.send(display: .input(1))
        store.send(command: .getState(Crosswind_Agent_GetState()), id: 9)
        #expect(await store.inbox.first { $0.commandResult?.id == 9 } != nil)

        stubA.send(display: .configure(1))
        #expect(await display.next() == ToGuest.configure(1))
    }

    @Test func guestDisplayEndingClosesEveryOpenWindowForItsStub() async throws {
        let harness = AgentHarness()
        let display = await harness.attachDisplay()
        let stubA = harness.connect(.stub, appID: "org.example.A")
        let stubB = harness.connect(.stub, appID: "org.example.B")

        display.send(.opened(1, flatpakID: "org.example.A"))
        display.send(.opened(2, flatpakID: "org.example.B"))
        display.send(.opened(3, flatpakID: "org.example.A"))
        _ = await stubA.nextDisplay()
        _ = await stubA.nextDisplay()
        _ = await stubB.nextDisplay()

        display.disconnect()

        var closedByA: [UInt32] = []
        for _ in 0..<2 {
            if case .closed(let closed)? = await stubA.nextDisplay()?.msg { closedByA.append(closed.id) }
        }
        #expect(closedByA.sorted() == [1, 3])
        #expect(await stubB.nextDisplay() == ToHost.closed(2))
    }

    // MARK: Commands

    @Test func stubsMayOnlyLaunchTheirOwnAppAndStoreGetsState() async throws {
        let harness = AgentHarness()
        let guest = harness.attachGuest()
        let stub = harness.connect(.stub, appID: "org.example.A")
        let store = harness.connect(.store)

        // A launch for another app is dropped: no guest request and no command result. The request after it
        // proves the launch was handled first, since a stub's messages arrive in order.
        stub.send(command: .launchApp(.with { $0.appID = "org.example.B" }))
        stub.send(request: listRunningRequest(id: 1))
        let request = try #require(await within { await guest.nextRequest() })
        guard case .listRunning? = request.body else {
            Issue.record("expected listRunning first, got \(String(describing: request.body))")
            return
        }
        guest.reply(to: request, .running(Crosswind_Control_RunningList()))

        let next = await stub.inbox.first { $0.guestResponse != nil || $0.commandResult != nil }
        #expect(next?.guestResponse?.id == 1)

        store.send(command: .getState(Crosswind_Agent_GetState()), id: 7)
        let result = try #require(await store.inbox.first { $0.commandResult?.id == 7 }?.commandResult)
        #expect(result.error.isEmpty)
        #expect(result.state.phase == .stopped)
    }

    // MARK: Disconnects

    @Test func stubDisconnectStopsItsApp() async throws {
        let harness = AgentHarness()
        let guest = harness.attachGuest()
        let stub = harness.connect(.stub, appID: "org.example.A")

        stub.disconnect()

        let request = try #require(await within { await guest.nextRequest() })
        guard case .stop(let stop)? = request.body else {
            Issue.record("expected a stop request, got \(String(describing: request.body))")
            return
        }
        #expect(stop.appID == "org.example.A")
        guest.reply(to: request, .ok(Crosswind_Control_Ok()))
    }

    // MARK: State

    @Test func newClientsReceiveCurrentStateAndChangesAreBroadcast() async throws {
        let harness = AgentHarness()
        let early = harness.connect(.store)
        #expect(await early.inbox.next()?.stateUpdate?.runningApps == [])

        harness.session.apply(
            .with {
                $0.body = .appStarted(
                    .with {
                        $0.appID = "org.example.A"
                        $0.pid = 1
                    })
            })
        #expect(await early.inbox.first { $0.stateUpdate?.runningApps == ["org.example.A"] } != nil)

        let late = harness.connect(.store)
        #expect(await late.inbox.next()?.stateUpdate?.runningApps == ["org.example.A"])
    }

    // MARK: Share refresh

    @Test func refreshSharesIsAllowedForStubsStoreAndCtl() async throws {
        let harness = AgentHarness()
        let stub = harness.connect(.stub, appID: "org.example.A")
        let store = harness.connect(.store)
        let ctl = harness.connect(.ctl)

        // With no VM running the refresh is a successful no-op.
        stub.send(command: .refreshShares(.init()), id: 1)
        let fromStub = try #require(await stub.inbox.first { $0.commandResult?.id == 1 }?.commandResult)
        #expect(fromStub.error.isEmpty)
        store.send(command: .refreshShares(.init()), id: 2)
        let fromStore = try #require(await store.inbox.first { $0.commandResult?.id == 2 }?.commandResult)
        #expect(fromStore.error.isEmpty)
        ctl.send(command: .refreshShares(.init()), id: 3)
        let fromCtl = try #require(await ctl.inbox.first { $0.commandResult?.id == 3 }?.commandResult)
        #expect(fromCtl.error.isEmpty)
    }

    @Test func stubsMayNotSendCommandsOtherThanLaunchAndRefreshShares() async throws {
        let harness = AgentHarness()
        let stub = harness.connect(.stub, appID: "org.example.A")

        // The stop is dropped without a result. The refresh after it is answered, so the stop had its chance.
        stub.send(command: .stopVm(.init()), id: 4)
        stub.send(command: .refreshShares(.init()), id: 5)
        let answered = await stub.inbox.first { $0.commandResult?.id == 5 }
        #expect(answered?.commandResult?.error.isEmpty == true)
        #expect(await stub.inbox.first(timeout: .milliseconds(300)) { $0.commandResult?.id == 4 } == nil)
    }

    @Test func stubPolicyAllowsOnlyItsLaunchAndRefresh() {
        #expect(StubCommandPolicy.allows(.launchApp(.with { $0.appID = "org.example.A" }), appID: "org.example.A"))
        #expect(!StubCommandPolicy.allows(.launchApp(.with { $0.appID = "org.example.B" }), appID: "org.example.A"))
        #expect(StubCommandPolicy.allows(.refreshShares(.init()), appID: "org.example.A"))
        #expect(!StubCommandPolicy.allows(.stopVm(.init()), appID: "org.example.A"))
        #expect(!StubCommandPolicy.allows(nil, appID: "org.example.A"))
    }
}
