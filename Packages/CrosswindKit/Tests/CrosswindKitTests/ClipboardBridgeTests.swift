// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Testing

@testable import CrosswindKit

@MainActor
private final class FakePasteboard: ClipboardPasteboard {
    private(set) var changeCount = 0
    private var contents: [String: Data] = [:]
    private(set) var writes: [[String]] = []  // types written per set(), in order
    private(set) var lastWrite: [(type: String, data: Data)] = []

    func types() -> [String] { Array(contents.keys) }

    func data(for type: String) -> Data? { contents[type] }

    func set(_ items: [(type: String, data: Data)]) -> Int {
        contents = [:]
        for item in items { contents[item.type] = item.data }
        writes.append(items.map(\.type))
        lastWrite = items
        changeCount += 1
        return changeCount
    }

    /// Simulates the user copying on the Mac.
    func copy(_ items: [String: Data]) {
        contents = items
        changeCount += 1
    }
}

@MainActor
private final class FakeFrontmost: ClipboardFrontmost {
    var isStubFrontmost = false
}

@MainActor
private final class FakeTimer: ClipboardTimer {
    private(set) var fire: (@MainActor () -> Void)?
    var isScheduled: Bool { fire != nil }

    func schedule(every seconds: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        self.fire = fire
    }

    func cancel() { fire = nil }

    func tick() { fire?() }
}

@MainActor
private final class Harness {
    let pasteboard = FakePasteboard()
    let frontmost = FakeFrontmost()
    let timer = FakeTimer()
    var enabled = true
    var offers: [[String]] = []
    var replies: [Crosswind_Control_CallReply] = []
    private(set) var bridge: ClipboardBridge!

    init() {
        bridge = ClipboardBridge(
            pasteboard: pasteboard, frontmost: frontmost, timer: timer,
            isEnabled: { [unowned self] in self.enabled },
            sendToGuest: { [unowned self] body in
                if case .offerClipboard(let offer) = body { self.offers.append(offer.mimes) }
            },
            replyToCall: { [unowned self] reply in self.replies.append(reply) })
    }

    /// A Crosswind stub comes to the front.
    func activateStub() {
        frontmost.isStubFrontmost = true
        bridge.frontmostChanged()
    }

    func read(_ mime: String, callID: UInt64 = 1) {
        bridge.read(callID: callID, mime: mime)
    }
}

private func text(_ mime: String, _ string: String) -> Crosswind_Control_ClipboardData {
    .with {
        $0.mime = mime
        $0.data = Data(string.utf8)
    }
}

/// A 2x2 TIFF, as the Mac puts on the pasteboard for screenshots.
private func tiffFixture() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.tiffRepresentation!
}

private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

@MainActor
@Suite struct ClipboardBridgeTests {
    @Test func offersTypesOnActivation() {
        let h = Harness()
        h.pasteboard.copy(["public.utf8-plain-text": Data("hi".utf8)])
        h.activateStub()
        #expect(h.offers == [["text/plain;charset=utf-8"]])
        #expect(h.timer.isScheduled)
    }

    @Test func noOfferAndNoPollingWhileNotFrontmost() {
        let h = Harness()
        h.pasteboard.copy(["public.utf8-plain-text": Data("hi".utf8)])
        h.bridge.frontmostChanged()
        #expect(h.offers.isEmpty)
        #expect(!h.timer.isScheduled)
    }

    @Test func offersAgainWhenMacCopiesWhileStubFrontmost() {
        let h = Harness()
        h.activateStub()
        h.timer.tick()
        #expect(h.offers.count == 1)  // no change, no offer
        h.pasteboard.copy(["public.png": Data([1, 2, 3])])
        h.timer.tick()
        #expect(h.offers.last == ["image/png"])
        #expect(h.offers.count == 2)
    }

    @Test func stopsPollingWhenStubLosesFocus() {
        let h = Harness()
        h.activateStub()
        h.frontmost.isStubFrontmost = false
        h.bridge.frontmostChanged()
        #expect(!h.timer.isScheduled)
    }

    @Test func emptyOfferWhenPasteboardHasNothingSupported() {
        let h = Harness()
        h.pasteboard.copy(["com.apple.some-private-type": Data([0])])
        h.activateStub()
        #expect(h.offers == [[]])
    }

    @Test func mimeMappingCoversTiffAndHtml() {
        let types = ["public.utf8-plain-text", "public.tiff", "public.html", "com.example.other"]
        #expect(ClipboardBridge.offeredMimes(for: types) == ["text/plain;charset=utf-8", "image/png", "text/html"])
        #expect(ClipboardBridge.offeredMimes(for: ["public.png"]) == ["image/png"])
        #expect(ClipboardBridge.offeredMimes(for: []).isEmpty)
    }

    @Test func noDataSentWhileNotFrontmost() {
        let h = Harness()
        h.pasteboard.copy(["public.utf8-plain-text": Data("secret".utf8)])
        h.read("text/plain;charset=utf-8", callID: 7)
        #expect(h.replies.count == 1)
        #expect(h.replies[0].id == 7)
        guard case .error(let error)? = h.replies[0].result else {
            Issue.record("expected an error reply")
            return
        }
        #expect(error.message == "clipboard unavailable")
    }

    @Test func textReadReturnsDataWhileFrontmost() {
        let h = Harness()
        h.pasteboard.copy(["public.utf8-plain-text": Data("hello".utf8)])
        h.activateStub()
        h.read("text/plain;charset=utf-8")
        #expect(h.replies[0].clipboard.mime == "text/plain;charset=utf-8")
        #expect(h.replies[0].clipboard.data == Data("hello".utf8))
    }

    @Test func tiffIsConvertedToPNGOnRead() {
        let h = Harness()
        h.pasteboard.copy(["public.tiff": tiffFixture()])
        h.activateStub()
        h.read("image/png")
        let png = h.replies[0].clipboard.data
        #expect(Array(png.prefix(4)) == pngSignature)
    }

    @Test func unsupportedMimeIsRefused() {
        let h = Harness()
        h.pasteboard.copy(["public.utf8-plain-text": Data("x".utf8)])
        h.activateStub()
        h.read("application/x-secret")
        guard case .error? = h.replies[0].result else {
            Issue.record("expected an error reply")
            return
        }
    }

    @Test func textLimitIsOneMiB() {
        let h = Harness()
        h.activateStub()
        h.pasteboard.copy(["public.utf8-plain-text": Data(count: ClipboardBridge.textLimit)])
        h.read("text/plain;charset=utf-8")
        #expect(h.replies[0].clipboard.data.count == ClipboardBridge.textLimit)

        h.pasteboard.copy(["public.utf8-plain-text": Data(count: ClipboardBridge.textLimit + 1)])
        h.read("text/plain;charset=utf-8", callID: 2)
        guard case .error? = h.replies[1].result else {
            Issue.record("expected an error reply over 1 MiB")
            return
        }
    }

    @Test func imageLimitIsSixteenMiB() {
        let h = Harness()
        h.activateStub()
        h.pasteboard.copy(["public.png": Data(count: ClipboardBridge.imageLimit + 1)])
        h.read("image/png")
        guard case .error? = h.replies[0].result else {
            Issue.record("expected an error reply over 16 MiB")
            return
        }
    }

    @Test func echoOfGuestCopyIsNotOfferedBack() {
        let h = Harness()
        h.activateStub()
        h.bridge.guestCopied([text("text/plain;charset=utf-8", "from linux")])
        h.timer.tick()
        #expect(h.offers.count == 1)
        #expect(h.pasteboard.writes.count == 1)
    }

    @Test func macCopyAfterGuestCopyIsOfferedAgain() {
        let h = Harness()
        h.activateStub()
        h.bridge.guestCopied([text("text/plain;charset=utf-8", "from linux")])
        h.pasteboard.copy(["public.png": Data([1])])
        h.timer.tick()
        #expect(h.offers.last == ["image/png"])
    }

    @Test func guestCopiesWriteMappedTypesAndDropOversizeItems() {
        let h = Harness()
        h.bridge.guestCopied([
            text("text/plain", "plain"),
            .with {
                $0.mime = "image/png"
                $0.data = Data([9, 9])
            },
            text("text/html", "<b>x</b>"),
            text("application/unknown", "dropped"),
            .with {
                $0.mime = "text/plain"
                $0.data = Data(count: ClipboardBridge.textLimit + 1)
            },
        ])
        #expect(h.pasteboard.lastWrite.map(\.type) == ["public.utf8-plain-text", "public.png", "public.html"])
        #expect(h.pasteboard.lastWrite[1].data == Data([9, 9]))
    }

    @Test func syncOffSendsEmptyOfferAndIgnoresGuestCopies() {
        let h = Harness()
        h.enabled = false
        h.pasteboard.copy(["public.utf8-plain-text": Data("hi".utf8)])
        h.activateStub()
        #expect(h.offers == [[]])

        h.bridge.guestCopied([text("text/plain", "from linux")])
        #expect(h.pasteboard.writes.isEmpty)

        h.read("text/plain;charset=utf-8")
        guard case .error(let error)? = h.replies[0].result else {
            Issue.record("expected an error reply")
            return
        }
        #expect(error.message == "clipboard unavailable")
    }
}
