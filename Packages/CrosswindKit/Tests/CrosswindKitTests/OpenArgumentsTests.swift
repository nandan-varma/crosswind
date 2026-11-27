// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite struct OpenArgumentsTests {
    @Test func filesBecomeGuestPathsAndLinksPassThrough() {
        let urls = [URL(fileURLWithPath: "/Users/me/a.txt"), URL(string: "tg://resolve?domain=example")!]
        let args = OpenArguments.make(from: urls) { "/mnt/mac/Docs/" + $0.lastPathComponent }
        #expect(args == ["/mnt/mac/Docs/a.txt", "tg://resolve?domain=example"])
    }

    @Test func aFileThatCannotBeMappedIsDropped() {
        #expect(OpenArguments.make(from: [URL(fileURLWithPath: "/x")]) { _ in nil }.isEmpty)
    }

    @Test func aLinkNeverStartsWithADashSoItCannotBecomeAnOption() {
        let args = OpenArguments.make(from: [URL(string: "magnet:?xt=urn:btih:abc")!]) { _ in nil }
        #expect(args.allSatisfy { !$0.hasPrefix("-") })
    }

    @Test func schemesComeFromSchemeHandlerMediaTypes() {
        let types = [
            "image/png", "x-scheme-handler/tg", "x-scheme-handler/magnet", "x-scheme-handler/tg", "x-scheme-handler/",
        ]
        #expect(StubInstaller.urlSchemes(for: types) == ["magnet", "tg"])
        #expect(StubInstaller.contentTypes(for: types) == ["public.png"])
    }
}
