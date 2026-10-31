// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

@testable import CrosswindKit

/// Runs `operation` and returns its result, or nil if it has not finished within `timeout`.
func within<T: Sendable>(
    _ timeout: Duration = .seconds(5),
    _ operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask { () -> T? in
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next().flatMap { $0 }
        group.cancelAll()
        return first
    }
}

/// Buffers an AsyncStream behind a single consumer so tests can wait for elements with a timeout.
final class Inbox<Element: Sendable>: @unchecked Sendable {
    private var iterator: AsyncStream<Element>.Iterator

    init(_ stream: AsyncStream<Element>) { iterator = stream.makeAsyncIterator() }

    func next(timeout: Duration = .seconds(5)) async -> Element? {
        await within(timeout) { await self.iterator.next() }
    }

    /// Discards elements until one matches; nil on timeout or end of stream.
    func first(timeout: Duration = .seconds(5), where matches: @Sendable (Element) -> Bool) async -> Element? {
        while let element = await next(timeout: timeout) {
            if matches(element) { return element }
        }
        return nil
    }
}

/// Owns both ends of a socketpair. The connections keep it alive, so the descriptors close with the last of them.
final class SocketPairOwner: @unchecked Sendable {
    let fds: [Int32]

    init() {
        var fds: [Int32] = [0, 0]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        self.fds = fds
    }

    deinit {
        for fd in fds {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }
}

/// A client's end of an agent connection (store, crosswindctl or stub).
final class TestClient: @unchecked Sendable {
    let connection: ClientConnection
    let inbox: Inbox<Crosswind_Agent_AgentMessage>

    init(connection: ClientConnection) {
        self.connection = connection
        inbox = Inbox(connection.messages)
    }

    func send(request: Crosswind_Control_Request) {
        connection.send(.with { $0.request = request })
    }

    func send(command body: Crosswind_Agent_Command.OneOf_Body, id: UInt64 = 1) {
        connection.send(
            .with {
                $0.command = .with {
                    $0.id = id
                    $0.body = body
                }
            })
    }

    func send(display: Crosswind_Display_ToGuest) {
        connection.send(.with { $0.display = display })
    }

    /// Ends the client side; the agent sees end of stream.
    func disconnect() { connection.disconnect() }

    func nextDisplay() async -> ToHost? {
        await inbox.first { $0.displayMessage != nil }?.displayMessage
    }
}

/// The guest's display channel. The agent sends its output description first; `awaitOutput` consumes it.
final class FakeDisplay: @unchecked Sendable {
    let host: DisplayConnection
    private let peer: FramedConnection<ToGuest, ToHost>
    private let inbox: Inbox<ToGuest>

    init() {
        let owner = SocketPairOwner()
        host = DisplayConnection(fd: owner.fds[0], owner: owner)
        peer = FramedConnection(fd: owner.fds[1], owner: owner)
        inbox = Inbox(peer.messages)
    }

    func awaitOutput() async {
        _ = await inbox.first { message in
            if case .output? = message.msg { return true }
            return false
        }
    }

    /// The next message the agent sends to the guest.
    func next() async -> ToGuest? { await inbox.next() }

    func send(_ message: ToHost) { peer.send(message) }

    /// Closes the guest end; the agent sees end of stream.
    func disconnect() { peer.disconnect() }
}

extension Crosswind_Agent_AgentMessage {
    var guestMessage: Crosswind_Control_Message? {
        if case .guest(let message)? = body { return message }
        return nil
    }

    var guestResponse: Crosswind_Control_Response? {
        if case .response(let response)? = guestMessage?.body { return response }
        return nil
    }

    var guestEvent: Crosswind_Control_Event.OneOf_Body? {
        if case .event(let event)? = guestMessage?.body { return event.body }
        return nil
    }

    var stateUpdate: Crosswind_Agent_State? {
        if case .state(let state)? = body { return state }
        return nil
    }

    var commandResult: Crosswind_Agent_CommandResult? {
        if case .result(let result)? = body { return result }
        return nil
    }

    var displayMessage: ToHost? {
        if case .display(let message)? = body { return message }
        return nil
    }
}

extension Crosswind_Control_Response {
    var errorMessage: String? {
        if case .error(let error)? = result { return error.message }
        return nil
    }
}

extension ToHost {
    static func opened(_ id: UInt32, flatpakID: String = "", appID: String = "") -> ToHost {
        .with {
            $0.msg = .opened(
                .with {
                    $0.id = id
                    $0.flatpakID = flatpakID
                    $0.appID = appID
                })
        }
    }

    static func frame(_ window: UInt32) -> ToHost {
        .with { $0.msg = .frame(.with { $0.window = window }) }
    }

    static func changed(_ id: UInt32, title: String) -> ToHost {
        .with {
            $0.msg = .changed(
                .with {
                    $0.id = id
                    $0.title = title
                })
        }
    }

    static func closed(_ id: UInt32) -> ToHost {
        .with { $0.msg = .closed(.with { $0.id = id }) }
    }
}

extension ToGuest {
    static func input(_ window: UInt32) -> ToGuest {
        .with { $0.msg = .input(.with { $0.window = window }) }
    }

    static func configure(_ window: UInt32) -> ToGuest {
        .with { $0.msg = .configure(.with { $0.window = window }) }
    }

    static func ack(_ window: UInt32) -> ToGuest {
        .with { $0.msg = .ack(.with { $0.window = window }) }
    }

    static func closeRequest(_ window: UInt32) -> ToGuest {
        .with { $0.msg = .close(.with { $0.window = window }) }
    }
}

/// Wires an AgentCore to a fake guest (control and display channels) and hands out fake clients.
@MainActor
final class AgentHarness {
    let session = GuestSession(paths: GuestPaths(supportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())))
    let core: AgentCore

    init() {
        core = AgentCore(session: session, output: { Crosswind_Display_Output() }, openURL: { _ in true })
    }

    func connect(_ role: Crosswind_Agent_Role, appID: String = "") -> TestClient {
        let owner = SocketPairOwner()
        core.accept(AgentConnection(fd: owner.fds[0], owner: owner), role: role, appID: appID)
        return TestClient(connection: ClientConnection(fd: owner.fds[1], owner: owner))
    }

    func attachGuest() -> FakeGuest {
        let guest = FakeGuest()
        session.onControl?(guest.host)
        return guest
    }

    func attachDisplay() async -> FakeDisplay {
        let display = FakeDisplay()
        session.onDisplay?(display.host)
        await display.awaitOutput()
        return display
    }
}
