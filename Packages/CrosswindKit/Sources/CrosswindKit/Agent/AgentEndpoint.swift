// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
@preconcurrency import XPC

public enum AgentService {
    /// Mach service the host agent registers with launchd (see the LaunchAgent plist in the app bundle).
    public static let machService = "dev.crosswind.host"
    fileprivate static let roleKey = "role"
    fileprivate static let appKey = "app_id"
    fileprivate static let fdKey = "fd"
}

public enum AgentConnectError: Error {
    case unavailable
    case rejected
}

/// Agent side: the Mach service that launchd starts the agent for. Each accepted XPC connection is a handshake
/// that hands the client one end of a socketpair; the framed protocol then runs over that socket.
public final class AgentEndpoint: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.crosswind.agent.xpc")
    private let accept: @Sendable (AgentConnection, Crosswind_Agent_Role, String) -> Void
    private var listener: xpc_connection_t?

    /// `accept` runs on an arbitrary queue.
    public init(accept: @escaping @Sendable (AgentConnection, Crosswind_Agent_Role, String) -> Void) {
        self.accept = accept
    }

    public func resume() {
        let listener = xpc_connection_create_mach_service(
            AgentService.machService, queue, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        xpc_connection_set_event_handler(listener) { [weak self] peer in
            guard let self, xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }
            self.serve(peer)
        }
        xpc_connection_resume(listener)
        self.listener = listener
    }

    private func serve(_ peer: xpc_connection_t) {
        xpc_connection_set_event_handler(peer) { [weak self] message in
            guard let self, xpc_get_type(message) == XPC_TYPE_DICTIONARY else { return }
            self.handshake(message, from: peer)
        }
        xpc_connection_resume(peer)
    }

    private func handshake(_ message: xpc_object_t, from peer: xpc_connection_t) {
        guard let reply = xpc_dictionary_create_reply(message) else { return }
        let role = Crosswind_Agent_Role(rawValue: Int(xpc_dictionary_get_int64(message, AgentService.roleKey)))
        let appID = xpc_dictionary_get_string(message, AgentService.appKey).map { String(cString: $0) } ?? ""
        var fds: [Int32] = [0, 0]
        guard let role, socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            xpc_connection_send_message(peer, reply)
            return
        }
        xpc_dictionary_set_fd(reply, AgentService.fdKey, fds[1])
        xpc_connection_send_message(peer, reply)
        close(fds[1])
        accept(AgentConnection(fd: fds[0], closesDescriptor: true), role, appID)
    }
}

/// Client side: connects to the agent (launchd starts it on demand) and says who it is.
public enum AgentClientConnector {
    public static func connect(role: Crosswind_Agent_Role, appID: String = "") async throws -> ClientConnection {
        let queue = DispatchQueue(label: "dev.crosswind.client.xpc")
        let service = xpc_connection_create_mach_service(AgentService.machService, queue, 0)
        xpc_connection_set_event_handler(service) { _ in }
        xpc_connection_resume(service)

        let request = xpc_dictionary_create_empty()
        xpc_dictionary_set_int64(request, AgentService.roleKey, Int64(role.rawValue))
        xpc_dictionary_set_string(request, AgentService.appKey, appID)

        let fd: Int32 = try await withCheckedThrowingContinuation { continuation in
            xpc_connection_send_message_with_reply(service, request, queue) { reply in
                guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY else {
                    continuation.resume(throwing: AgentConnectError.unavailable)
                    return
                }
                let fd = xpc_dictionary_dup_fd(reply, AgentService.fdKey)
                if fd < 0 {
                    continuation.resume(throwing: AgentConnectError.rejected)
                } else {
                    continuation.resume(returning: fd)
                }
            }
        }
        xpc_connection_cancel(service)
        return ClientConnection(fd: fd, closesDescriptor: true)
    }
}
