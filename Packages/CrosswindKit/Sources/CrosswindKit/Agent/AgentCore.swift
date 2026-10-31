// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The agent's end of a client connection.
public typealias AgentConnection = FramedConnection<Crosswind_Agent_ClientMessage, Crosswind_Agent_AgentMessage>
/// A client's end (store, crosswindctl, stub).
public typealias ClientConnection = FramedConnection<Crosswind_Agent_AgentMessage, Crosswind_Agent_ClientMessage>

/// Owns the guest and routes between it and the agent's clients.
///
/// - Guest control responses go back to the requesting client (ids are remapped per connection);
///   guest control events are broadcast to every client.
/// - Display messages are routed by Flatpak app id: each stub receives only its own app's windows and can
///   only send input for windows it owns.
@MainActor
public final class AgentCore {
    private final class Client {
        let connection: AgentConnection
        let role: Crosswind_Agent_Role
        let appID: String
        init(connection: AgentConnection, role: Crosswind_Agent_Role, appID: String) {
            self.connection = connection
            self.role = role
            self.appID = appID
        }
    }

    private struct ForwardedRequest {
        let client: ObjectIdentifier?  // nil: the agent's own request
        let clientRequestID: UInt64
        let reply: ((Crosswind_Control_Response) -> Void)?
    }

    private let session: GuestSession
    private var clients: [ObjectIdentifier: Client] = [:]
    private var stubs: [String: Client] = [:]
    private struct WindowRecord {
        var app: String
        var title: String
        var width: UInt32 = 0
        var height: UInt32 = 0
        var scale120: UInt32 = 0
        var frames: UInt64 = 0
        var lastInput: ContinuousClock.Instant?
        var lastLatencyMs = 0.0
    }

    private var windows: [UInt32: WindowRecord] = [:]
    private var displayToGuest: DisplayConnection?
    private var controlToGuest: ControlConnection?
    private var inflight: [UInt64: ForwardedRequest] = [:]
    private var nextGuestRequestID: UInt64 = 0

    /// Describes the host display to the guest (main screen size, scale, refresh rate).
    private let output: () -> Crosswind_Display_Output

    public init(session: GuestSession, output: @escaping () -> Crosswind_Display_Output) {
        self.session = session
        self.output = output
        session.onStateChange = { [weak self] state in self?.broadcast(.with { $0.state = state }) }
        session.onDisplay = { [weak self] in self?.attach(display: $0) }
        session.onControl = { [weak self] in self?.attach(control: $0) }
        session.onReady = { [weak self] in try await self?.greetGuest() }
    }

    /// Takes ownership of a freshly accepted client connection.
    public func accept(_ connection: AgentConnection, role: Crosswind_Agent_Role, appID: String) {
        let client = Client(connection: connection, role: role, appID: appID)
        clients[ObjectIdentifier(client)] = client
        if role == .stub, !appID.isEmpty { stubs[appID] = client }
        connection.send(.with { $0.state = session.state })
        Task { [weak self] in
            for await message in connection.messages { self?.handle(message, from: client) }
            self?.disconnected(client)
        }
    }

    // MARK: Clients

    private func handle(_ message: Crosswind_Agent_ClientMessage, from client: Client) {
        switch message.body {
        case .request(let request)?:
            forward(request, from: client)
        case .command(let command)?:
            if client.role == .stub {  // a stub may only launch its own app
                guard case .launchApp(let launch)? = command.body, launch.appID == client.appID else { return }
            }
            run(command, for: client)
        case .display(let input)?:
            guard client.role == .stub, owns(client, window: windowID(of: input)) else { return }
            send(input)
        case nil:
            break
        }
    }

    private func disconnected(_ client: Client) {
        clients.removeValue(forKey: ObjectIdentifier(client))
        guard client.role == .stub, stubs[client.appID] === client else { return }
        stubs.removeValue(forKey: client.appID)
        // A closed stub is a quit: stop the app it represented.
        Task { _ = try? await request(.stop(.with { $0.appID = client.appID })) }
    }

    private func broadcast(_ message: Crosswind_Agent_AgentMessage) {
        for client in clients.values { client.connection.send(message) }
    }

    // MARK: Guest control

    private func attach(control connection: ControlConnection) {
        controlToGuest = connection
        Task { [weak self] in
            for await message in connection.messages { self?.route(guest: message) }
            self?.controlToGuest = nil
            self?.session.guestEnded()
        }
    }

    private func forward(_ request: Crosswind_Control_Request, from client: Client) {
        let id = issue(ForwardedRequest(client: ObjectIdentifier(client), clientRequestID: request.id, reply: nil))
        var outgoing = request
        outgoing.id = id
        controlToGuest?.send(outgoing)
    }

    /// The agent's own request to the guest (e.g. `hello`).
    func request(_ body: Crosswind_Control_Request.OneOf_Body) async throws -> Crosswind_Control_Response {
        guard controlToGuest != nil else { throw GuestControlError.disconnected }
        return await withCheckedContinuation { continuation in
            let id = issue(ForwardedRequest(client: nil, clientRequestID: 0, reply: { continuation.resume(returning: $0) }))
            controlToGuest?.send(.with {
                $0.id = id
                $0.body = body
            })
        }
    }

    private func issue(_ request: ForwardedRequest) -> UInt64 {
        nextGuestRequestID += 1
        inflight[nextGuestRequestID] = request
        return nextGuestRequestID
    }

    private func route(guest message: Crosswind_Control_Message) {
        switch message.body {
        case .response(var response)?:
            guard let request = inflight.removeValue(forKey: response.id) else { return }
            if let reply = request.reply { return reply(response) }
            guard let key = request.client, let client = clients[key] else { return }
            response.id = request.clientRequestID
            client.connection.send(.with { $0.guest = .with { $0.response = response } })
        case .event(let event)?:
            session.apply(event)
            broadcast(.with { $0.guest = message })
        case nil:
            break
        }
    }

    // MARK: Commands

    private func run(_ command: Crosswind_Agent_Command, for client: Client) {
        let reply = { (error: String) in
            client.connection.send(.with {
                $0.result = .with {
                    $0.id = command.id
                    $0.error = error
                    $0.state = self.session.state
                    $0.windows = self.info()
                }
            })
        }
        Task {
            do {
                switch command.body {
                case .startVm?: try await ensureRunning()
                case .stopVm?: await session.stop()
                case .getState?, .listWindows?: break
                case .injectInput(let inject)?:
                    guard client.role == .ctl else { throw GuestSessionError.guest("not permitted") }
                    send(.with { $0.input = inject.input })
                case .launchApp(let launch)?:
                    try await ensureRunning()
                    let response = try await request(.launch(.with { $0.appID = launch.appID; $0.args = launch.args }))
                    if case .error(let error)? = response.result { throw GuestSessionError.guest(error.message) }
                case nil: break
                }
                reply("")
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    private func ensureRunning() async throws {
        try await session.ensureRunning()
    }

    private func greetGuest() async throws {
        let hello = Crosswind_Control_Hello.with {
            $0.unixTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
            $0.timeZone = TimeZone.current.identifier
            $0.locale = Locale.current.identifier + ".UTF-8"
        }
        let response = try await request(.hello(hello))
        if case .error(let error)? = response.result { throw GuestSessionError.guest(error.message) }
    }

    // MARK: Display

    private func attach(display connection: DisplayConnection) {
        displayToGuest = connection
        connection.send(.with { $0.output = output() })
        Task { [weak self] in
            for await message in connection.messages { self?.route(display: message) }
            self?.guestDisplayEnded()
        }
    }

    private func route(display message: ToHost) {
        switch message.msg {
        case .opened(let opened)?:
            let app = opened.flatpakID.isEmpty ? opened.appID : opened.flatpakID
            windows[opened.id] = WindowRecord(app: app, title: opened.title)
            send(message, toStubOf: app)
        case .changed(let changed)?:
            if changed.hasTitle { windows[changed.id]?.title = changed.title }
            send(message, toStubOfWindow: changed.id)
        case .closed(let closed)?:
            send(message, toStubOfWindow: closed.id)
            windows.removeValue(forKey: closed.id)
        case .frame(let frame)?:
            record(frame)
            send(message, toStubOfWindow: frame.window)
        case .cursor(let cursor)?: send(message, toStubOfWindow: cursor.window)
        case nil: break
        }
    }

    private func send(_ message: ToHost, toStubOfWindow window: UInt32) {
        guard let app = windows[window]?.app else { return }
        send(message, toStubOf: app)
    }

    private func send(_ message: ToHost, toStubOf app: String) {
        stubs[app]?.connection.send(.with { $0.display = message })
    }

    private func guestDisplayEnded() {
        displayToGuest = nil
        for (window, record) in windows {
            send(.with { $0.closed = .with { $0.id = window } }, toStubOf: record.app)
        }
        windows.removeAll()
    }

    private func record(_ frame: Crosswind_Display_Frame) {
        guard var record = windows[frame.window] else { return }
        record.frames += 1
        record.width = frame.width
        record.height = frame.height
        record.scale120 = frame.scale120
        if let start = record.lastInput {
            let elapsed = ContinuousClock.now - start
            record.lastLatencyMs = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3
            record.lastInput = nil
        }
        windows[frame.window] = record
    }

    private func info() -> [Crosswind_Agent_WindowInfo] {
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
    private func send(_ input: ToGuest) {
        if case .input(let value)? = input.msg, windows[value.window] != nil {
            if case .leave? = value.event {} else { windows[value.window]?.lastInput = .now }
        }
        displayToGuest?.send(input)
    }

    private func owns(_ client: Client, window: UInt32) -> Bool { windows[window]?.app == client.appID }

    private func windowID(of input: ToGuest) -> UInt32 {
        switch input.msg {
        case .configure(let value)?: value.window
        case .ack(let value)?: value.window
        case .input(let value)?: value.window
        case .close(let value)?: value.window
        case .output?, nil: 0
        }
    }
}
