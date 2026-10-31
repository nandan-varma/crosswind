// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Foundation

/// The Mac pasteboard as the clipboard bridge sees it. `SystemPasteboard` is the real one; tests use a fake.
@MainActor
public protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    /// Pasteboard type identifiers (UTIs) currently on the clipboard.
    func types() -> [String]
    func data(for type: String) -> Data?
    /// Replaces the contents and returns the change count the write produced.
    func set(_ items: [(type: String, data: Data)]) -> Int
}

/// Whether a Crosswind app stub is the frontmost application.
@MainActor
public protocol ClipboardFrontmost {
    var isStubFrontmost: Bool { get }
}

/// A repeating timer on the main run loop.
@MainActor
public protocol ClipboardTimer: AnyObject {
    func schedule(every seconds: TimeInterval, _ fire: @escaping @MainActor () -> Void)
    func cancel()
}

/// Shares the clipboard between the Mac and the Linux guest.
///
/// - Mac to guest is lazy: while a Crosswind app is frontmost, the bridge offers the MIME types on the Mac clipboard.
///   Data is sent only when the guest pastes (`ClipboardRead`), and only while a Crosswind app is still frontmost.
/// - Guest to Mac is eager: copied items are written to the Mac clipboard. The resulting change is not offered back.
@MainActor
public final class ClipboardBridge {
    public static let textLimit = 1 << 20
    public static let imageLimit = 16 << 20
    public static let pollInterval: TimeInterval = 0.3
    public static let unavailable = "clipboard unavailable"

    private enum UTI {
        static let plainText = "public.utf8-plain-text"
        static let png = "public.png"
        static let tiff = "public.tiff"
        static let html = "public.html"
    }

    private enum Kind: Equatable {
        case text, png, html
    }

    private struct Refusal: Error {
        let message: String
    }

    private let pasteboard: ClipboardPasteboard
    private let frontmost: ClipboardFrontmost
    private let timer: ClipboardTimer
    private let isEnabled: () -> Bool
    private let sendToGuest: (Crosswind_Control_Request.OneOf_Body) -> Void
    private let replyToCall: (Crosswind_Control_CallReply) -> Void
    /// Change count at the last offer or our own write. A different count means the Mac copied something new.
    private var lastSeenCount: Int
    private var activation: NSObjectProtocol?

    /// - Parameters:
    ///   - isEnabled: the `clipboardSync` preference. When false, offers are empty and guest copies are ignored.
    ///   - sendToGuest: sends a fire-and-forget request to the guest.
    ///   - replyToCall: answers a guest `Call`.
    public init(
        pasteboard: ClipboardPasteboard,
        frontmost: ClipboardFrontmost,
        timer: ClipboardTimer,
        isEnabled: @escaping () -> Bool,
        sendToGuest: @escaping (Crosswind_Control_Request.OneOf_Body) -> Void,
        replyToCall: @escaping (Crosswind_Control_CallReply) -> Void
    ) {
        self.pasteboard = pasteboard
        self.frontmost = frontmost
        self.timer = timer
        self.isEnabled = isEnabled
        self.sendToGuest = sendToGuest
        self.replyToCall = replyToCall
        self.lastSeenCount = pasteboard.changeCount
    }

    /// Observes app activation. Call once, at startup.
    public func start() {
        guard activation == nil else { return }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        frontmostChanged()
    }

    /// Called on every application activation. Starts polling and offers the clipboard while a stub is frontmost.
    public func frontmostChanged() {
        guard frontmost.isStubFrontmost else {
            timer.cancel()
            return
        }
        lastSeenCount = pasteboard.changeCount
        timer.schedule(every: Self.pollInterval) { [weak self] in self?.poll() }
        offer()
    }

    /// Answers a guest paste. Refused unless a Crosswind app is frontmost right now.
    public func read(callID: UInt64, mime: String) {
        var reply = Crosswind_Control_CallReply()
        reply.id = callID
        do {
            let data = try payload(forMime: mime)
            reply.clipboard = .with {
                $0.mime = mime
                $0.data = data
            }
        } catch let refusal as Refusal {
            reply.error = .with { $0.message = refusal.message }
        } catch {
            reply.error = .with { $0.message = Self.unavailable }
        }
        replyToCall(reply)
    }

    /// Writes items the guest copied to the Mac clipboard. Items over the size limits or of unknown types are dropped.
    public func guestCopied(_ items: [Crosswind_Control_ClipboardData]) {
        guard isEnabled() else { return }
        let accepted: [(type: String, data: Data)] = items.compactMap { item in
            guard let kind = Self.kind(of: item.mime), item.data.count <= Self.limit(for: kind) else { return nil }
            return (Self.type(of: kind), item.data)
        }
        guard !accepted.isEmpty else { return }
        lastSeenCount = pasteboard.set(accepted)
    }

    // MARK: Mac to guest

    private func poll() {
        guard frontmost.isStubFrontmost else {
            timer.cancel()
            return
        }
        let count = pasteboard.changeCount
        guard count != lastSeenCount else { return }
        lastSeenCount = count
        offer()
    }

    private func offer() {
        let mimes = isEnabled() ? Self.offeredMimes(for: pasteboard.types()) : []
        sendToGuest(.offerClipboard(.with { $0.mimes = mimes }))
    }

    private func payload(forMime mime: String) throws -> Data {
        guard isEnabled(), frontmost.isStubFrontmost else { throw Refusal(message: Self.unavailable) }
        guard let kind = Self.kind(of: mime) else { throw Refusal(message: "unsupported clipboard type \(mime)") }
        switch kind {
        case .text, .html:
            let type = kind == .text ? UTI.plainText : UTI.html
            guard let data = pasteboard.data(for: type) else { throw Refusal(message: "no \(mime) on the Mac") }
            guard data.count <= Self.textLimit else { throw Refusal(message: "clipboard text exceeds 1 MiB") }
            return data
        case .png:
            guard let data = pngData() else { throw Refusal(message: "no image on the Mac") }
            guard data.count <= Self.imageLimit else { throw Refusal(message: "clipboard image exceeds 16 MiB") }
            return data
        }
    }

    /// PNG as stored, or the TIFF on the clipboard converted to PNG.
    private func pngData() -> Data? {
        if let png = pasteboard.data(for: UTI.png) { return png }
        guard let tiff = pasteboard.data(for: UTI.tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Mapping

    /// The MIME types offered for the given pasteboard types. Empty when nothing supported is present.
    static func offeredMimes(for types: [String]) -> [String] {
        var mimes: [String] = []
        if types.contains(UTI.plainText) { mimes.append("text/plain;charset=utf-8") }
        if types.contains(UTI.png) || types.contains(UTI.tiff) { mimes.append("image/png") }
        if types.contains(UTI.html) { mimes.append("text/html") }
        return mimes
    }

    private static func kind(of mime: String) -> Kind? {
        let base = mime.split(separator: ";", maxSplits: 1).first.map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        switch base {
        case "text/plain": return .text
        case "image/png": return .png
        case "text/html": return .html
        default: return nil
        }
    }

    private static func type(of kind: Kind) -> String {
        switch kind {
        case .text: UTI.plainText
        case .png: UTI.png
        case .html: UTI.html
        }
    }

    private static func limit(for kind: Kind) -> Int {
        kind == .png ? imageLimit : textLimit
    }
}

/// `NSPasteboard.general`.
@MainActor
public final class SystemPasteboard: ClipboardPasteboard {
    private let pasteboard = NSPasteboard.general

    public init() {}

    public var changeCount: Int { pasteboard.changeCount }

    public func types() -> [String] { pasteboard.types?.map(\.rawValue) ?? [] }

    public func data(for type: String) -> Data? { pasteboard.data(forType: NSPasteboard.PasteboardType(type)) }

    public func set(_ items: [(type: String, data: Data)]) -> Int {
        pasteboard.clearContents()
        for item in items {
            pasteboard.setData(item.data, forType: NSPasteboard.PasteboardType(item.type))
        }
        return pasteboard.changeCount
    }
}

/// The frontmost app is a stub: bundle id `dev.crosswind.app.*`, launched from `~/Applications/Crosswind`.
@MainActor
public struct SystemFrontmost: ClipboardFrontmost {
    public init() {}

    public var isStubFrontmost: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier, let bundleURL = app.bundleURL
        else { return false }
        let stubs = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Crosswind").path
        return bundleID.hasPrefix("dev.crosswind.app.") && bundleURL.path.hasPrefix(stubs + "/")
    }
}

/// A main run loop timer.
@MainActor
public final class SystemTimer: ClipboardTimer {
    private var timer: Timer?

    public init() {}

    public func schedule(every seconds: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            MainActor.assumeIsolated { fire() }
        }
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
