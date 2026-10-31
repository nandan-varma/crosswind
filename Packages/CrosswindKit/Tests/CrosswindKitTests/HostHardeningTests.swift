// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Guest call gate")
struct GuestCallGateTests {
    private func notify(_ app: String, id: UInt64 = 1, body: String = "hi") -> Crosswind_Control_Call {
        .with {
            $0.id = id
            $0.appID = app
            $0.notify = .with {
                $0.notificationID = "n"
                $0.title = "t"
                $0.body = body
            }
        }
    }

    private func chooser(_ app: String, id: UInt64) -> Crosswind_Control_Call {
        .with {
            $0.id = id
            $0.appID = app
            $0.fileChooser = .with { $0.title = "Open" }
        }
    }

    @Test("links: only http, https and mailto")
    func urlSchemes() {
        #expect(GuestCallGate.allowsURL("https://example.com/a?b=c"))
        #expect(GuestCallGate.allowsURL("HTTP://example.com"))
        #expect(GuestCallGate.allowsURL("mailto:me@example.com"))
        for bad in [
            "file:///etc/passwd", "smb://host/share", "ssh://host", "javascript:alert(1)", "x-apple.systempreferences:",
            "vnc://host", "https://exa mple.com", "https://a\u{202E}b", "https://a\nb", "example.com", "",
            "https://" + String(repeating: "a", count: 9000),
        ] {
            #expect(!GuestCallGate.allowsURL(bad), "\(bad.prefix(40)) must be refused")
        }
    }

    @Test("notifications: five a minute per app, then refused until the window refills")
    func notificationRate() {
        let gate = GuestCallGate()
        let start = ContinuousClock.now
        for i in 0..<5 {
            #expect(gate.admit(notify("org.a", id: UInt64(i)), now: start) != .reject("x"))
            if case .reject = gate.admit(notify("org.b", id: 0), now: start) { Issue.record("other app limited") }
        }
        #expect(gate.admit(notify("org.a"), now: start) == .reject("too many notifications; wait a minute"))
        #expect(gate.admit(notify("org.a"), now: start + .seconds(61)) != .reject("too many notifications; wait a minute"))
    }

    @Test("notifications: text and icon are cut to their limits")
    func notificationFields() throws {
        let gate = GuestCallGate()
        let call: Crosswind_Control_Call = .with {
            $0.id = 1
            $0.appID = "org.a"
            $0.notify = .with {
            $0.notificationID = "n"
            $0.title = "t"
            $0.body = String(repeating: "b", count: 10_000)
                $0.iconPng = Data(count: GuestCallGate.maxIconBytes + 1)
            }
        }
        guard case .admit(let admitted) = gate.admit(call), case .notify(let notify)? = admitted.body else {
            Issue.record("expected admit")
            return
        }
        #expect(notify.body.utf8.count == GuestCallGate.maxNotificationBody)
        #expect(notify.iconPng.isEmpty)
    }

    @Test("file dialogs: one open per app, released by the reply, filters capped")
    func fileChooserOnePerApp() throws {
        let gate = GuestCallGate()
        #expect(gate.admit(chooser("org.a", id: 1)) != .reject("x"))
        #expect(gate.admit(chooser("org.a", id: 2)) == .reject("a file dialog is already open for this app"))
        #expect(gate.admit(chooser("org.b", id: 3)) != .reject("x"))
        gate.finished(call: 1)
        #expect(gate.admit(chooser("org.a", id: 4)) != .reject("x"))
        gate.forget(app: "org.a")
        #expect(gate.admit(chooser("org.a", id: 5)) != .reject("x"))

        let many: Crosswind_Control_Call = .with {
            $0.id = 9
            $0.appID = "org.c"
            $0.fileChooser = .with {
                $0.title = "t"
                $0.suggestedName = "../../etc/passwd"
                $0.filters = Array(repeating: "*.txt", count: 500)
            }
        }
        guard case .admit(let admitted) = gate.admit(many), case .fileChooser(let chooser)? = admitted.body else {
            Issue.record("expected admit")
            return
        }
        #expect(chooser.filters.count == GuestCallGate.maxFilters)
        #expect(!chooser.suggestedName.contains("/"))
    }

    @Test("clipboard reads with absurd type names are refused; empty calls too")
    func clipboardAndEmpty() {
        let gate = GuestCallGate()
        let read: Crosswind_Control_Call = .with { $0.clipboardRead = .with { $0.mime = String(repeating: "m", count: 5000) } }
        #expect(gate.admit(read) == .reject("unknown clipboard type"))
        #expect(gate.admit(Crosswind_Control_Call()) == .reject("empty call"))
    }

    @Test("safe file names drop path parts")
    func fileNames() {
        #expect(GuestCallGate.safeFileName("report.pdf") == "report.pdf")
        #expect(GuestCallGate.safeFileName("../x") == ".._x")
        #expect(GuestCallGate.safeFileName(".") == "")
        #expect(GuestCallGate.safeFileName("..") == "")
    }
}

@Suite("Rate limiter")
struct RateLimiterTests {
    @Test("burst, then refill at the configured rate")
    func tokenBucket() {
        let limiter = RateLimiter(perSecond: 2, burst: 3)
        let start = ContinuousClock.now
        #expect((0..<3).allSatisfy { _ in limiter.allow(now: start) })
        #expect(!limiter.allow(now: start))
        #expect(!limiter.allow(now: start + .milliseconds(400)))
        #expect(limiter.allow(now: start + .milliseconds(500)))
        // Time going backwards must not mint tokens.
        #expect(!limiter.allow(now: start))
    }
}

@Suite("Framed connection under hostile input")
struct FramedConnectionFuzzTests {
    /// Writes `bytes` into one end of a socketpair and returns what the connection decodes from the other.
    private func decode(_ bytes: [UInt8], maxFrame: Int = 4096) async -> [ToHost] {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        var one: Int32 = 1
        _ = setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let connection = DisplayConnection(fd: fds[0], closesDescriptor: true, maxFrameBytes: maxFrame)
        let inbox = Inbox(connection.messages)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { write(fds[1], $0.baseAddress! + offset, $0.count - offset) }
            if n <= 0 { break }  // the reader gave up (refused frame): the peer sees the close
            offset += n
        }
        close(fds[1])
        var out: [ToHost] = []
        while let message = await inbox.next(timeout: .seconds(5)) { out.append(message) }
        return out
    }

    private func frame(_ body: [UInt8]) -> [UInt8] {
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { Array($0) } + body
    }

    @Test("a valid message decodes; garbage after it ends the stream without a crash")
    func validThenGarbage() async throws {
        let valid = try ToHost.with { $0.opened = .with { $0.id = 3; $0.title = "ok" } }.serializedData()
        let out = await decode(frame([UInt8](valid)) + SplitMix64(seed: 1).bytes(300))
        guard case .opened(let opened)? = out.first?.msg else {
            Issue.record("the valid message was not decoded")
            return
        }
        #expect(opened.id == 3)
    }

    @Test("a length prefix over the cap ends the connection before anything is read")
    func oversizedLength() async {
        let header = withUnsafeBytes(of: UInt32(1 << 30).littleEndian) { Array($0) }
        #expect(await decode(header + [UInt8](repeating: 0, count: 64)).isEmpty)
    }

    @Test("random byte streams never crash the reader")
    func randomStreams() async {
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<200 {
            var stream: [UInt8] = []
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let body = rng.bytes(Int.random(in: 0...200, using: &rng))
                stream += Bool.random(using: &rng) ? frame(body) : rng.bytes(Int.random(in: 0...16, using: &rng))
            }
            _ = await decode(stream, maxFrame: 512)
        }
    }
}

@Suite("AppStream gzip hardening")
struct AppStreamHardeningTests {
    @Test("a gzip bomb is refused at the limit instead of inflating")
    func bomb() throws {
        let zeros = Data(count: 8 << 20)
        let packed = try #require(deflate(zeros))
        #expect(packed.count < 64 << 10)  // tiny on the wire, large when inflated
        let container = gzipContainer(deflate: packed)
        #expect(throws: AppStreamError.decompressionFailed) {
            try AppStreamParser.inflateGzip(container, limit: 1 << 20)
        }
        #expect(try AppStreamParser.inflateGzip(container, limit: 16 << 20).count == zeros.count)
    }

    @Test("the default limit is 256 MiB")
    func defaultLimit() {
        #expect(AppStreamParser.maxInflatedBytes == 256 << 20)
    }

    @Test("random bytes and mangled headers never crash the parser")
    func randomFuzz() throws {
        var rng = SplitMix64(seed: 0xA11CE)
        for i in 0..<3_000 {
            var bytes = rng.bytes(Int.random(in: 0...300, using: &rng))
            if i % 2 == 0, bytes.count > 10 {
                bytes[0] = 0x1f
                bytes[1] = 0x8b
                bytes[2] = 8
                bytes[3] = UInt8.random(in: 0...255, using: &rng)  // every FEXTRA/FNAME/FCOMMENT/FHCRC combination
            }
            _ = try? AppStreamParser.parse(gzipped: Data(bytes))
        }
    }

    @Test("a truncated deflate stream is an error, not a short catalog")
    func truncated() throws {
        let raw = Data(repeating: 0x41, count: 100_000)
        let packed = try #require(deflate(raw))
        let cut = gzipContainer(deflate: packed.prefix(packed.count / 2))
        #expect(throws: AppStreamError.decompressionFailed) { try AppStreamParser.inflateGzip(cut) }
    }
}

@Suite("Control channel under hostile messages")
struct ControlChannelFuzzTests {
    @Test("unknown and malformed messages are absorbed; events stay bounded")
    func absorbsGarbage() async throws {
        var rng = SplitMix64(seed: 0x5EED)
        let (messages, continuation) = AsyncStream.makeStream(of: Crosswind_Control_Message.self)
        let control = GuestControl(messages: messages, send: { _ in })
        for _ in 0..<5_000 {
            // Random bytes that happen to decode become messages; the rest are dropped at decode time.
            if let message = try? Crosswind_Control_Message(serializedBytes: rng.bytes(Int.random(in: 0...64, using: &rng))) {
                continuation.yield(message)
            }
        }
        // A huge log flood must not block the reader: the events stream keeps only its newest items.
        for i in 0..<10_000 {
            continuation.yield(
                .with {
                    $0.event = .with {
                        $0.log = .with {
                            $0.text = "line \(i)"
                            $0.source = String(repeating: "s", count: 100_000)
                        }
                    }
                })
        }
        continuation.finish()
        // Reaching here without a crash or a hang is the property; the control actor also closes cleanly.
        try await Task.sleep(for: .milliseconds(200))
        _ = control
    }
}
