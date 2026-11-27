// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

// What the user reads when something fails. Without these, Swift shows "The operation couldn't be completed
// (CrosswindKit.GuestControlError error 1.)". Each message says what happened and, where there is one, what to do.

extension GuestControlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .remote(let message): message
        case .disconnected:
            String(localized: "The Linux environment stopped while this was running. Try again.")
        case .cancelled: String(localized: "Cancelled.")
        case .unexpectedResponse:
            String(
                localized: "The Linux environment answered in an unexpected way. Restart it in Settings and try again.")
        }
    }
}

extension AgentCommandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .failed(let message): message
        case .disconnected:
            String(localized: "Crosswind lost its connection to the background agent. Try again.")
        }
    }
}

extension AgentConnectError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "The background agent isn't available. Allow it under Login Items & Extensions in Settings.")
        case .rejected:
            String(localized: "The background agent refused the connection. Reinstall Crosswind if this continues.")
        }
    }
}

extension GuestSessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noControlChannel:
            String(localized: "The Linux environment started but did not respond. Restart it in Settings.")
        case .guest(let message): message
        }
    }
}

extension StubError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTemplate:
            String(localized: "The template for Mac apps is damaged. Reinstall Crosswind.")
        case .signingFailed(let detail):
            String(localized: "Couldn't create the Mac app for this Linux app. \(detail)")
        }
    }
}

extension ImageStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sizeMismatch(let file), .checksumMismatch(let file):
            String(localized: "The downloaded Linux environment failed verification (\(file)). Try again.")
        }
    }
}

extension FlathubError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .badStatus(let status):
            String(localized: "Flathub returned an error (\(status)). Try again later.")
        case .invalidResponse:
            String(localized: "Flathub sent an answer Crosswind couldn't read. Try again later.")
        }
    }
}

extension AppStreamError: LocalizedError {
    public var errorDescription: String? {
        String(localized: "The app catalog couldn't be read. Refresh it and try again.")
    }
}

extension IconRendererError: LocalizedError {
    public var errorDescription: String? {
        String(localized: "The app's icon couldn't be used.")
    }
}
