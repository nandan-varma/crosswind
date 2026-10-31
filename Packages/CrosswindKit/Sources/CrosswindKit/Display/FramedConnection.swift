// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SwiftProtobuf

public typealias ToHost = Crosswind_Display_ToHost
public typealias ToGuest = Crosswind_Display_ToGuest

/// Largest message body accepted from the peer; a longer length prefix ends the connection.
public let defaultMaxFrameBytes = 64 << 20

public typealias DisplayConnection = FramedConnection<ToHost, ToGuest>

/// A vsock stream carrying length-prefixed (little-endian u32) protobuf messages.
/// Reads run on a dedicated thread; writes are serialized on a queue.
public final class FramedConnection<Incoming: SwiftProtobuf.Message & Sendable, Outgoing: SwiftProtobuf.Message>:
    @unchecked Sendable
{
    private let fd: Int32
    private let owner: AnyObject?  // keeps the VZVirtioSocketConnection alive
    private let writeQueue = DispatchQueue(label: "dev.crosswind.vsock.write")

    public let messages: AsyncStream<Incoming>
    private let continuation: AsyncStream<Incoming>.Continuation

    /// `closesDescriptor`: the connection owns `fd` (a socketpair end) and closes it when the stream ends.
    public init(
        fd: Int32, owner: AnyObject? = nil, closesDescriptor: Bool = false, maxFrameBytes: Int = defaultMaxFrameBytes
    ) {
        self.fd = fd
        self.owner = owner
        (messages, continuation) = AsyncStream.makeStream(of: Incoming.self, bufferingPolicy: .unbounded)
        let fd = fd
        let continuation = continuation
        let maxFrame = maxFrameBytes
        Thread.detachNewThread {
            Self.readLoop(fd: fd, maxFrame: maxFrame, continuation: continuation)
            if closesDescriptor { close(fd) }
        }
    }

    /// Ends the stream: pending reads fail, the peer sees EOF.
    public func disconnect() {
        shutdown(fd, SHUT_RDWR)
    }

    public func send(_ message: Outgoing) {
        guard let body = try? message.serializedData() else { return }
        var frame = Data(capacity: 4 + body.count)
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        let bytes = frame
        writeQueue.async { [fd] in
            bytes.withUnsafeBytes { buf in
                var offset = 0
                while offset < buf.count {
                    let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                    if n < 0 && errno == EINTR { continue }
                    if n <= 0 { return }
                    offset += n
                }
            }
        }
    }

    private static func readLoop(fd: Int32, maxFrame: Int, continuation: AsyncStream<Incoming>.Continuation) {
        defer { continuation.finish() }
        var header = [UInt8](repeating: 0, count: 4)
        while readExactly(fd, &header, 4) {
            let length = Int(UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            guard length <= maxFrame else { return }
            var body = [UInt8](repeating: 0, count: length)
            guard readExactly(fd, &body, length) else { return }
            guard let message = try? Incoming(serializedBytes: body) else { return }
            continuation.yield(message)
        }
    }

    private static func readExactly(_ fd: Int32, _ buffer: inout [UInt8], _ count: Int) -> Bool {
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress! + offset, count - offset) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return false }
            offset += n
        }
        return true
    }
}
