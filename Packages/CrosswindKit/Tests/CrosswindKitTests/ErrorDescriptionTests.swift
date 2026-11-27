// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite struct ErrorDescriptionTests {
    private let errors: [any Error] = [
        GuestControlError.remote("flatpak failed"), GuestControlError.disconnected, GuestControlError.cancelled,
        GuestControlError.unexpectedResponse, AgentCommandError.failed("not allowed"), AgentCommandError.disconnected,
        AgentConnectError.unavailable, AgentConnectError.rejected, GuestSessionError.noControlChannel,
        GuestSessionError.guest("guest said no"), StubError.invalidTemplate, StubError.signingFailed("codesign failed"),
        ImageStoreError.sizeMismatch("Image"), ImageStoreError.checksumMismatch("Image"), FlathubError.badStatus(503),
        FlathubError.invalidResponse, AppStreamError.notGzip, AppStreamError.decompressionFailed,
        IconRendererError.undecodableImage, IconRendererError.renderFailed,
    ]

    @Test func everyUserFacingErrorReadsAsASentence() {
        for error in errors {
            let text = error.localizedDescription
            #expect(!text.contains("error 1"), "\(error) has no description")
            #expect(!text.contains("CrosswindKit."), "\(error) falls back to Swift's default text")
            #expect(text.count > 8, "\(error) has an empty description")
        }
    }

    @Test func messagesFromTheGuestPassThroughUnchanged() {
        #expect(GuestControlError.remote("app not found").localizedDescription == "app not found")
    }
}
