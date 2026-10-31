// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

@testable import CrosswindKit

/// Guest end of a socketpair. Reads Requests and writes Messages with the same framing as the device.
/// Tests use it from one task at a time, so `nextRequest` has a single consumer.
final class FakeGuest: @unchecked Sendable {
    let host: ControlConnection
    private let peer: FramedConnection<Crosswind_Control_Request, Crosswind_Control_Message>
    private var requests: AsyncStream<Crosswind_Control_Request>.Iterator
    private let fds: [Int32]

    init() {
        var fds: [Int32] = [0, 0]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        self.fds = fds
        let owner = NSObject()
        host = ControlConnection(fd: fds[0], owner: owner)
        peer = FramedConnection(fd: fds[1], owner: owner)
        requests = peer.messages.makeAsyncIterator()
    }

    deinit {
        for fd in fds {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }

    func nextRequest() async -> Crosswind_Control_Request? {
        await requests.next()
    }

    func send(_ message: Crosswind_Control_Message) {
        peer.send(message)
    }

    func reply(to request: Crosswind_Control_Request, _ result: Crosswind_Control_Response.OneOf_Result) {
        send(.response(id: request.id, result))
    }

    /// Closes the guest end; the host sees end of stream.
    func disconnect() {
        shutdown(fds[1], SHUT_RDWR)
    }
}

extension Crosswind_Control_Message {
    static func response(id: UInt64, _ result: Crosswind_Control_Response.OneOf_Result) -> Self {
        .with {
            $0.body = .response(
                Crosswind_Control_Response.with {
                    $0.id = id
                    $0.result = result
                })
        }
    }

    static func event(_ body: Crosswind_Control_Event.OneOf_Body) -> Self {
        .with { $0.body = .event(Crosswind_Control_Event.with { $0.body = body }) }
    }
}

extension Crosswind_Control_Request {
    /// The operation a Cancel request refers to, or nil for other requests.
    var cancelledOperation: UInt64? {
        guard case .cancel(let cancel)? = body else { return nil }
        return cancel.operation
    }
}

extension GuestControl {
    /// Test convenience: drive the control client straight over a vsock-style connection.
    init(connection: ControlConnection) {
        self.init(messages: connection.messages, send: { connection.send($0) })
    }
}
