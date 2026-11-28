// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// What went wrong with an app operation, in terms the user can act on. The guest reports Flatpak's own error text
/// ("error: Failed to install ...: No space left on device"); this turns the common causes into a plain sentence and
/// tells the store whether trying again can work by itself.
public struct Failure: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Flathub or the network could not be reached. Trying again later helps.
        case offline
        /// The environment's data disk is full. The user has to remove something first.
        case diskFull
        /// Flathub has no such app for this Mac.
        case notFound
        /// The Linux environment stopped while the operation ran. Starting it again and retrying helps.
        case environmentStopped
        case other
    }

    public var kind: Kind
    public var message: String

    /// Whether the store may start the environment again and repeat the operation without asking.
    public var retriesAutomatically: Bool { kind == .environmentStopped }

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public init(_ error: Error) {
        switch error {
        case GuestControlError.disconnected, AgentCommandError.disconnected, GuestSessionError.noControlChannel:
            self.init(
                kind: .environmentStopped,
                message: String(localized: "The Linux environment stopped while this was running."))
        case GuestControlError.remote(let text), GuestSessionError.guest(let text):
            self = Self.classify(guestMessage: text) ?? Failure(kind: .other, message: text)
        default:
            self.init(kind: .other, message: error.localizedDescription)
        }
    }

    /// Recognizes the failures Flatpak reports most often. Nil for anything else, so the original text stays.
    static func classify(guestMessage text: String) -> Failure? {
        let lower = text.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { lower.contains($0) } }
        if has("no space left", "not enough disk space", "disk quota") {
            return Failure(
                kind: .diskFull,
                message: String(
                    localized: """
                        The Linux environment is out of disk space. Remove apps you no longer use, or reset the \
                        environment in Settings, then try again.
                        """))
        }
        let offlineSigns = [
            "could not resolve", "temporary failure in name resolution", "network is unreachable", "timed out",
            "unable to load summary", "failed to connect", "connection refused", "connection reset", "no route to host",
        ]
        if offlineSigns.contains(where: lower.contains) {
            return Failure(
                kind: .offline,
                message: String(
                    localized: "Crosswind couldn't reach Flathub. Check your internet connection and try again."))
        }
        if has("no remote refs found", "nothing matches", "not found in remote", "no such ref") {
            return Failure(
                kind: .notFound,
                message: String(
                    localized: "Flathub has no version of this app that runs on this Mac. It may have been removed."))
        }
        return nil
    }
}
