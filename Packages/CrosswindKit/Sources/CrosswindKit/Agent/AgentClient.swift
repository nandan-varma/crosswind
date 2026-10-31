// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum AgentCommandError: Error, Equatable {
    case failed(String)
    case disconnected
}

/// A client of the host agent (store app, crosswindctl, stub): guest control, VM state, display traffic and commands.
public actor AgentClient {
    /// Guest control as if connected to the guest directly; requests travel through the agent.
    public nonisolated let control: GuestControl
    /// The VM state, delivered on connect and on every change.
    public nonisolated let states: AsyncStream<Crosswind_Agent_State>
    /// Stubs only: window lifecycle and frames for this app's windows.
    public nonisolated let display: AsyncStream<ToHost>

    private let connection: ClientConnection
    private var nextID: UInt64 = 0
    private var pending: [UInt64: CheckedContinuation<Crosswind_Agent_CommandResult, Error>] = [:]

    public static func connect(role: Crosswind_Agent_Role, appID: String = "") async throws -> AgentClient {
        AgentClient(connection: try await AgentClientConnector.connect(role: role, appID: appID))
    }

    init(connection: ClientConnection) {
        self.connection = connection
        let guest = AsyncStream<Crosswind_Control_Message>.makeStream()
        let states = AsyncStream<Crosswind_Agent_State>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let display = AsyncStream<ToHost>.makeStream()
        let results = AsyncStream<Crosswind_Agent_CommandResult>.makeStream()
        control = GuestControl(messages: guest.stream, send: { request in connection.send(.with { $0.request = request }) })
        self.states = states.stream
        self.display = display.stream

        Task { [weak self] in
            for await message in connection.messages {
                switch message.body {
                case .guest(let value)?: guest.continuation.yield(value)
                case .state(let value)?: states.continuation.yield(value)
                case .display(let value)?: display.continuation.yield(value)
                case .result(let value)?: results.continuation.yield(value)
                case nil: break
                }
            }
            guest.continuation.finish()
            states.continuation.finish()
            display.continuation.finish()
            results.continuation.finish()
            await self?.failPending()
        }
        Task { [weak self] in
            for await result in results.stream { await self?.complete(result) }
        }
    }

    public func send(display message: ToGuest) {
        connection.send(.with { $0.display = message })
    }

    /// Runs an agent-level command and returns the agent's reply.
    public func command(_ body: Crosswind_Agent_Command.OneOf_Body) async throws -> Crosswind_Agent_State {
        nextID += 1
        let id = nextID
        let result = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            connection.send(.with {
                $0.command = .with {
                    $0.id = id
                    $0.body = body
                }
            })
        }
        if !result.error.isEmpty { throw AgentCommandError.failed(result.error) }
        return result.state
    }

    public func disconnect() { connection.disconnect() }

    private func complete(_ result: Crosswind_Agent_CommandResult) {
        pending.removeValue(forKey: result.id)?.resume(returning: result)
    }

    private func failPending() {
        for continuation in pending.values { continuation.resume(throwing: AgentCommandError.disconnected) }
        pending.removeAll()
    }
}
