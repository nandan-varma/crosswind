// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Diagnostics redaction")
struct DiagnosticsRedactorTests {
    private let redactor = Redactor(homeDirectory: "/Users/nandan", userName: "nandan")

    @Test("home directory and user name are replaced")
    func homeAndUser() {
        #expect(redactor.redact("/Users/nandan/Library/Application Support/Crosswind") == "~/Library/Application Support/Crosswind")
        #expect(redactor.redact("owner nandan launched it") == "owner <user> launched it")
    }

    @Test("email addresses are replaced")
    func email() {
        #expect(redactor.redact("contact nandanvarma.me@gmail.com today") == "contact <email> today")
    }

    @Test("public IPv4 is replaced, guest NAT addresses are kept")
    func ipv4() {
        #expect(redactor.redact("connect 203.0.113.7:443") == "connect <ipv4>:443")
        #expect(redactor.redact("10.0.0.1 and 8.8.8.8") == "<ipv4> and <ipv4>")
        #expect(redactor.redact("guest 192.168.64.2 gateway 192.168.64.1") == "guest 192.168.64.2 gateway 192.168.64.1")
    }

    @Test("IPv6 is replaced, clock times are kept")
    func ipv6() {
        #expect(redactor.redact("route fd00::1 up") == "route <ipv6> up")
        #expect(redactor.redact("2001:db8:85a3:0:0:8a2e:370:7334") == "<ipv6>")
        #expect(redactor.redact("at 12:34:56 done") == "at 12:34:56 done")
    }

    @Test("MAC addresses are replaced")
    func mac() {
        #expect(redactor.redact("ether 52:54:00:12:34:56 en0") == "ether <mac> en0")
        #expect(redactor.redact("ether 52-54-00-12-34-56") == "ether <mac>")
    }

    @Test("bearer tokens and long secrets are replaced")
    func tokens() {
        #expect(redactor.redact("Authorization: Bearer abc.def-123_xyz") == "Authorization: Bearer <redacted>")
        #expect(redactor.redact("key 9f2c4e8a7b1d0c3e5f6a9b8c7d6e5f4a") == "key <token>")
        #expect(redactor.redact("sha 3b1f9c0e7a2d4f6b8c0e1a3d5f7b9c2e4a6d8f0b") == "sha <token>")
    }

    @Test("URL query strings are dropped, the path is kept")
    func urlQuery() {
        #expect(redactor.redact("GET https://flathub.org/api/v2/app?token=abc&x=1 ok")
            == "GET https://flathub.org/api/v2/app?<redacted> ok")
        #expect(redactor.redact("https://flathub.org/apps") == "https://flathub.org/apps")
    }

    @Test("false positives: versions, short hashes, identifiers stay")
    func falsePositives() {
        let samples = [
            "macOS 26.1", "Flatpak 1.16.0", "version 51.1", "release 2026.10.31.1", "commit a1b2c3d",
            "short hash 9f8e7d6", "org.gnome.Calculator", "dev.crosswind.host", "app 46.0.2.1",
            "PID 4242", "size 1280x720", "frames 90210",
        ]
        for sample in samples {
            #expect(redactor.redact(sample) == sample, "\(sample) must not change")
        }
    }

    @Test("a realistic log excerpt keeps its structure")
    func realisticExcerpt() {
        let input = """
            2026-10-31 14:02:11 [crosswindd] info launch 7f3a: Bearer eyJhbGciOiJIUzI1NiJ9 from /Users/nandan/dev/x
            2026-10-31 14:02:12 [flatpak] warning remote https://dl.flathub.org/repo/?token=s3cret pinned 51.1
            2026-10-31 14:02:13 [org.gnome.Calculator] error mail nandanvarma.me@gmail.com ip 192.168.64.3 at 14:02:13
            """
        let output = redactor.redact(input)
        #expect(output.contains("[crosswindd] info launch 7f3a: Bearer <redacted> from ~/dev/x"))
        #expect(output.contains("https://dl.flathub.org/repo/?<redacted> pinned 51.1"))
        #expect(output.contains("mail <email> ip 192.168.64.3 at 14:02:13"))
        #expect(!output.contains("nandan"))
        #expect(!output.contains("s3cret"))
    }
}
