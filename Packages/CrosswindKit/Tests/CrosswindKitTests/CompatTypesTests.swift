// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Compatibility classification and results")
struct CompatTypesTests {
    private static func checks(
        window: CheckOutcome = .pass, renders: CheckOutcome = .pass, input: CheckOutcome = .pass,
        noCrash: CheckOutcome = .pass, exit: CheckOutcome = .pass, x11: Bool = false
    ) -> CompatChecks {
        var checks = CompatChecks()
        checks.windowAppears = window
        checks.renders = renders
        checks.inputWorks = input
        checks.noCrash = noCrash
        checks.cleanExit = exit
        checks.needsX11 = x11
        return checks
    }

    @Test("all checks passing is works")
    func worksWhenEverythingPasses() {
        #expect(CompatClassifier.status(for: Self.checks()) == .works)
    }

    @Test("unknown input or an unclean exit is works with caveats")
    func caveats() {
        #expect(CompatClassifier.status(for: Self.checks(input: .unknown)) == .caveats)
        #expect(CompatClassifier.status(for: Self.checks(exit: .fail)) == .caveats)
        #expect(CompatClassifier.status(for: Self.checks(x11: true)) == .caveats)
    }

    @Test("no window, a flat render or a crash is broken")
    func broken() {
        #expect(CompatClassifier.status(for: Self.checks(window: .fail)) == .broken)
        #expect(CompatClassifier.status(for: Self.checks(renders: .fail)) == .broken)
        #expect(CompatClassifier.status(for: Self.checks(noCrash: .fail)) == .broken)
    }

    @Test("skipped checks do not count as passes")
    func skippedIsBroken() {
        #expect(CompatClassifier.status(for: CompatChecks()) == .broken)
    }

    @Test("merge replaces by app id and sorts")
    func merge() {
        let when = Date(timeIntervalSince1970: 1_000)
        func record(_ id: String, _ status: CompatStatus) -> CompatRecord {
            CompatRecord(appID: id, name: id, status: status, testedAt: when, guestImageVersion: "1", arch: "aarch64")
        }
        let existing = [record("org.b.B", .broken), record("org.a.A", .works)]
        let merged = CompatResults.merge([record("org.b.B", .works), record("org.c.C", .caveats)], into: existing)
        #expect(merged.map(\.appID) == ["org.a.A", "org.b.B", "org.c.C"])
        #expect(merged[1].status == .works)
    }

    @Test("results survive a JSON round trip, including dates and nested checks")
    func roundTrip() throws {
        var checks = Self.checks(input: .unknown, x11: true)
        checks.cleanExit = .fail
        let when = Date(timeIntervalSince1970: 1_780_000_000)
        let record = CompatRecord(
            appID: "org.gnome.Calculator", name: "Calculator", status: .caveats, checks: checks,
            notes: ["did not exit"], testedAt: when, guestImageVersion: "0.4.0", appVersion: "49.1", arch: "aarch64",
            screenshot: "screenshots/org.gnome.Calculator.png")
        let data = try CompatResults.encode([record])
        #expect(try CompatResults.decode(data) == [record])
        #expect(String(decoding: data, as: UTF8.self).contains("\"no-arm-build\"") == false)
    }

    @Test("status raw values match the file format")
    func statusNames() {
        #expect(CompatStatus.noArmBuild.rawValue == "no-arm-build")
        #expect(CompatStatus.broken.title == "Known issues")
    }
}
