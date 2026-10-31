// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public typealias ControlConnection = FramedConnection<Crosswind_Control_Message, Crosswind_Control_Request>

public enum GuestControlError: Error, Equatable {
    /// The guest rejected a request or failed an operation with this message.
    case remote(String)
    /// The stream ended before the response or completion arrived.
    case disconnected
    case cancelled
    /// The guest answered with a result type that does not match the request.
    case unexpectedResponse
}

/// Host side of the control channel. Correlates requests with responses and routes guest events.
public actor GuestControl {
    public enum Event: Sendable {
        case log(Crosswind_Control_LogLine)
        case appStarted(Crosswind_Control_AppStarted)
        case appExited(Crosswind_Control_AppExited)
    }

    public nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation
    /// Requests the guest makes of the host (file dialogs, notifications); answer each with `reply(to:)`.
    public nonisolated let calls: AsyncStream<Crosswind_Control_Call>
    private let callContinuation: AsyncStream<Crosswind_Control_Call>.Continuation
    private let sendRequest: @Sendable (Crosswind_Control_Request) -> Void
    private var nextID: UInt64 = 0
    private var pending: [UInt64: (Result<Crosswind_Control_Response, Error>) -> Void] = [:]
    private var operations: [UInt64: OperationHandle] = [:]
    private var isClosed = false

    /// `messages` and `send` are the two directions of any transport (a vsock connection, or the host agent's socket).
    public init(
        messages: AsyncStream<Crosswind_Control_Message>,
        send: @escaping @Sendable (Crosswind_Control_Request) -> Void
    ) {
        sendRequest = send
        (events, eventContinuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        (calls, callContinuation) = AsyncStream.makeStream(of: Crosswind_Control_Call.self, bufferingPolicy: .unbounded)
        Task { [weak self] in
            for await message in messages {
                guard let self else { return }
                await self.route(message)
            }
            await self?.close()
        }
    }

    public func hello(darkMode: Bool = false) async throws {
        let hello = Crosswind_Control_Hello.with {
            $0.unixTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
            $0.timeZone = TimeZone.current.identifier
            $0.locale = Locale.current.identifier + ".UTF-8"
            $0.darkMode = darkMode
        }
        try await expectOk(.hello(hello))
    }

    public func refreshCatalog() async throws {
        try await expectOk(.refreshCatalog(Crosswind_Control_RefreshCatalog()))
    }

    public func catalog() async throws -> Data {
        guard case .catalog(let catalog) = try await call(.getCatalog(Crosswind_Control_GetCatalog())) else {
            throw GuestControlError.unexpectedResponse
        }
        return catalog.appstreamXmlGz
    }

    public func installed() async throws -> [Crosswind_Control_InstalledApp] {
        guard case .installed(let list) = try await call(.listInstalled(Crosswind_Control_ListInstalled())) else {
            throw GuestControlError.unexpectedResponse
        }
        return list.apps
    }

    public func running() async throws -> [Crosswind_Control_RunningApp] {
        guard case .running(let list) = try await call(.listRunning(Crosswind_Control_ListRunning())) else {
            throw GuestControlError.unexpectedResponse
        }
        return list.apps
    }

    public func launch(appID: String, args: [String] = []) async throws {
        let launch = Crosswind_Control_Launch.with {
            $0.appID = appID
            $0.args = args
        }
        try await expectOk(.launch(launch))
    }

    public func stop(appID: String) async throws {
        try await expectOk(.stop(Crosswind_Control_Stop.with { $0.appID = appID }))
    }

    public func permissions(appID: String) async throws -> Crosswind_Control_Permissions {
        let request = Crosswind_Control_GetPermissions.with { $0.appID = appID }
        guard case .permissions(let permissions) = try await call(.getPermissions(request)) else {
            throw GuestControlError.unexpectedResponse
        }
        return permissions
    }

    public func setPermissions(appID: String, _ permissions: Crosswind_Control_Permissions) async throws {
        let request = Crosswind_Control_SetPermissions.with {
            $0.appID = appID
            $0.permissions = permissions
        }
        try await expectOk(.setPermissions(request))
    }

    public func shutdown() async throws {
        try await expectOk(.shutdown(Crosswind_Control_Shutdown()))
    }

    public func install(appID: String) async throws -> OperationHandle {
        try await startOperation(.install(Crosswind_Control_Install.with { $0.appID = appID }))
    }

    public func uninstall(appID: String, deleteData: Bool = false) async throws -> OperationHandle {
        let request = Crosswind_Control_Uninstall.with {
            $0.appID = appID
            $0.deleteData = deleteData
        }
        return try await startOperation(.uninstall(request))
    }

    /// An empty `appID` updates everything installed.
    public func update(appID: String = "") async throws -> OperationHandle {
        try await startOperation(.update(Crosswind_Control_Update.with { $0.appID = appID }))
    }

    /// Answers a guest call.
    public func reply(to call: Crosswind_Control_Call, _ result: Crosswind_Control_CallReply.OneOf_Result) {
        sendRequest(
            .with {
                $0.callReply = .with {
                    $0.id = call.id
                    $0.result = result
                }
            })
    }

    func cancel(operation: UInt64) async throws {
        try await expectOk(.cancel(Crosswind_Control_Cancel.with { $0.operation = operation }))
    }

    private func expectOk(_ body: Crosswind_Control_Request.OneOf_Body) async throws {
        guard case .ok = try await call(body) else { throw GuestControlError.unexpectedResponse }
    }

    private func call(
        _ body: Crosswind_Control_Request.OneOf_Body
    ) async throws -> Crosswind_Control_Response.OneOf_Result {
        let response: Crosswind_Control_Response = try await withCheckedThrowingContinuation { continuation in
            send(body) { continuation.resume(with: $0) }
        }
        guard let result = response.result else { throw GuestControlError.unexpectedResponse }
        return result
    }

    /// Registers the handle before the reply is resumed, so no operation event can outrun its handle.
    private func startOperation(_ body: Crosswind_Control_Request.OneOf_Body) async throws -> OperationHandle {
        try await withCheckedThrowingContinuation { continuation in
            send(body) { reply in
                switch reply {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let response):
                    guard case .operation(let operation)? = response.result else {
                        continuation.resume(throwing: GuestControlError.unexpectedResponse)
                        return
                    }
                    let handle = OperationHandle(id: operation.id, control: self)
                    self.operations[operation.id] = handle
                    continuation.resume(returning: handle)
                }
            }
        }
    }

    private func send(
        _ body: Crosswind_Control_Request.OneOf_Body,
        reply: @escaping (Result<Crosswind_Control_Response, Error>) -> Void
    ) {
        guard !isClosed else {
            reply(.failure(GuestControlError.disconnected))
            return
        }
        nextID += 1
        let request = Crosswind_Control_Request.with {
            $0.id = nextID
            $0.body = body
        }
        pending[nextID] = reply
        sendRequest(request)
    }

    private func route(_ message: Crosswind_Control_Message) async {
        switch message.body {
        case .response(let response)?:
            let reply = pending.removeValue(forKey: response.id)
            if case .error(let error)? = response.result {
                reply?(.failure(GuestControlError.remote(error.message)))
            } else {
                reply?(.success(response))
            }
        case .event(let event)?:
            await route(event)
        case .call(let call)?:
            callContinuation.yield(call)
        case nil:
            break
        }
    }

    /// Progress and completion go to their operation handle only; other events go to `events`.
    /// Events for an operation whose response has not arrived yet are dropped.
    private func route(_ event: Crosswind_Control_Event) async {
        switch event.body {
        case .progress(let progress)?:
            await operations[progress.operation]?.deliver(progress)
        case .operationDone(let done)?:
            if let handle = operations.removeValue(forKey: done.operation) {
                await handle.finish(Self.outcome(of: done))
            }
        case .appStarted(let started)?:
            eventContinuation.yield(.appStarted(started))
        case .appExited(let exited)?:
            eventContinuation.yield(.appExited(exited))
        case .log(let line)?:
            eventContinuation.yield(.log(line))
        case .clipboardChanged?:
            break  // consumed by the agent's clipboard bridge
        case nil:
            break
        }
    }

    private static func outcome(of done: Crosswind_Control_OperationDone) -> Result<Void, Error> {
        if done.hasError { return .failure(GuestControlError.remote(done.error.message)) }
        if done.cancelled { return .failure(GuestControlError.cancelled) }
        return .success(())
    }

    private func close() async {
        isClosed = true
        let replies = Array(pending.values)
        pending.removeAll()
        for reply in replies { reply(.failure(GuestControlError.disconnected)) }
        let handles = Array(operations.values)
        operations.removeAll()
        for handle in handles { await handle.finish(.failure(GuestControlError.disconnected)) }
        eventContinuation.finish()
        callContinuation.finish()
    }
}
