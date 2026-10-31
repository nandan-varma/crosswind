// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Decides which guest-initiated calls (notifications, file dialogs, opening URLs, clipboard reads) reach the Mac,
/// and trims their fields to the limits below. The guest is untrusted: a call that breaks a rule is answered with
/// an error and never reaches a stub or the system.
final class GuestCallGate {
    static let notificationsPerMinute = 5
    static let maxNotifiers = 512
    static let maxURLBytes = 8192
    static let allowedURLSchemes: Set<String> = ["http", "https", "mailto"]
    static let maxFilters = 64
    static let maxPatternBytes = 256
    static let maxFieldBytes = 256
    static let maxIconBytes = 1 << 20
    static let maxNotificationBody = 2048
    static let maxMimeBytes = 64

    enum Verdict: Equatable {
        case admit(Crosswind_Control_Call)
        case reject(String)
    }

    private var notifiers: [String: RateLimiter] = [:]
    /// File dialogs in progress, by call id. One per app at a time.
    private var openChoosers: [UInt64: String] = [:]

    /// Applies the rules to one call from the guest.
    func admit(_ call: Crosswind_Control_Call, now: ContinuousClock.Instant = .now) -> Verdict {
        var call = call
        call.appID = DisplayLimits.sanitize(call.appID, maxBytes: Self.maxFieldBytes)
        switch call.body {
        case .notify(var notify)?:
            if !notify.withdraw {
                guard let limiter = notifier(for: call.appID), limiter.allow(now: now) else {
                    return .reject("too many notifications; wait a minute")
                }
            }
            notify.notificationID = DisplayLimits.sanitize(notify.notificationID, maxBytes: Self.maxFieldBytes)
            notify.title = DisplayLimits.sanitize(notify.title, maxBytes: Self.maxFieldBytes)
            notify.body = DisplayLimits.sanitize(notify.body, maxBytes: Self.maxNotificationBody)
            notify.defaultAction = DisplayLimits.sanitize(notify.defaultAction, maxBytes: Self.maxMimeBytes)
            if notify.iconPng.count > Self.maxIconBytes { notify.iconPng = Data() }
            call.body = .notify(notify)
            return .admit(call)

        case .openURL(let open)?:
            guard Self.allowsURL(open.url) else { return .reject("this kind of link cannot be opened from Linux") }
            return .admit(call)

        case .fileChooser(var chooser)?:
            guard !openChoosers.values.contains(call.appID) else {
                return .reject("a file dialog is already open for this app")
            }
            chooser.title = DisplayLimits.sanitize(chooser.title, maxBytes: Self.maxFieldBytes)
            chooser.suggestedName = Self.safeFileName(chooser.suggestedName)
            chooser.acceptLabel = DisplayLimits.sanitize(chooser.acceptLabel, maxBytes: Self.maxMimeBytes)
            chooser.filters = chooser.filters.prefix(Self.maxFilters).map {
                DisplayLimits.sanitize($0, maxBytes: Self.maxPatternBytes)
            }
            call.body = .fileChooser(chooser)
            openChoosers[call.id] = call.appID
            return .admit(call)

        case .clipboardRead(var read)?:
            guard read.mime.utf8.count <= Self.maxMimeBytes else { return .reject("unknown clipboard type") }
            read.mime = DisplayLimits.sanitize(read.mime, maxBytes: Self.maxMimeBytes)
            call.body = .clipboardRead(read)
            return .admit(call)

        case nil:
            return .reject("empty call")
        }
    }

    /// The host answered a file dialog, so the app may open another one.
    func finished(call id: UInt64) {
        openChoosers.removeValue(forKey: id)
    }

    /// The app's stub went away: its dialogs are over.
    func forget(app: String) {
        openChoosers = openChoosers.filter { $0.value != app }
    }

    private func notifier(for app: String) -> RateLimiter? {
        if let existing = notifiers[app] { return existing }
        guard notifiers.count < Self.maxNotifiers else { return nil }
        let limiter = RateLimiter(perMinute: Self.notificationsPerMinute)
        notifiers[app] = limiter
        return limiter
    }

    /// Only the schemes a Linux app may legitimately hand to the Mac: web links and mail.
    static func allowsURL(_ raw: String) -> Bool {
        guard raw.utf8.count <= maxURLBytes,
            !raw.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control }),
            let colon = raw.firstIndex(of: ":")
        else {
            return false
        }
        return allowedURLSchemes.contains(raw[..<colon].lowercased())
    }

    /// A suggested file name without path parts.
    static func safeFileName(_ raw: String) -> String {
        let name = DisplayLimits.sanitize(raw, maxBytes: maxFieldBytes).replacingOccurrences(of: "/", with: "_")
        return name == "." || name == ".." ? "" : name
    }
}
