// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite("Diagnostics log buffer and bundle")
struct DiagnosticsBufferTests {
    @Test("the buffer keeps only the newest entries")
    func ringKeepsNewest() {
        var buffer = LogRingBuffer(capacity: 3)
        for index in 1...10 {
            buffer.append(source: "crosswindd", level: 6, text: "line \(index)")
        }
        #expect(buffer.entries.map(\.text) == ["line 8", "line 9", "line 10"])
        #expect(buffer.entries.last?.id == 10)
    }

    @Test("the default capacity is 5,000 lines")
    func defaultCapacity() {
        #expect(LogRingBuffer().capacity == 5_000)
        var buffer = LogRingBuffer()
        for index in 1...5_001 {
            buffer.append(source: "app", level: 6, text: "\(index)")
        }
        #expect(buffer.entries.count == 5_000)
        #expect(buffer.entries.first?.text == "2")
    }

    @Test("levels map to names")
    func levelNames() {
        let entry = { (level: Int32) in
            LogEntry(id: 1, time: Date(), source: "s", level: level, launchID: "", text: "t")
        }
        #expect(entry(3).levelName == "error")
        #expect(entry(4).levelName == "warning")
        #expect(entry(6).levelName == "info")
        #expect(entry(7).levelName == "debug")
    }

    @Test("bundle files contain no home path, user name or email")
    func bundleIsRedacted() throws {
        let redactor = Redactor(homeDirectory: "/Users/nandan", userName: "nandan")
        let snapshot = DiagnosticSnapshot(
            system: SystemRecord(
                appVersion: "0.1", macOSVersion: "Version 27.0", model: "Mac15,6", memoryBytes: 1 << 34,
                generatedAt: Date(timeIntervalSince1970: 0)),
            agentState: AgentStateRecord(phase: "running", detail: "", runningApps: ["org.gnome.Calculator"]),
            windows: [WindowRecord(
                id: 3, appID: "org.gnome.Calculator", title: "Calculator for nandanvarma.me@gmail.com",
                width: 800, height: 600, scale120: 240, frames: 1234, lastInputToFrameMs: 12.5)],
            installed: nil,
            guestLogs: [Crosswind_Control_LogLine.with {
                $0.source = "crosswindd"
                $0.level = 6
                $0.launchID = "L1"
                $0.text = "mount /Users/nandan/vm from 10.1.2.3"
            }],
            hostLogs: [],
            reports: [ReportExcerpt(name: "CrosswindHost.ips", lines: ["Path: /Users/nandan/Crosswind"])],
            supportDirectoryBytes: 4096,
            problems: ["installed apps: disconnected"])
        let files = try DiagnosticBundle.files(for: snapshot, redactor: redactor)
        let names = Set(files.map(\.0))
        #expect(names.contains("system.json") && names.contains("agent-state.json") && names.contains("windows.json"))
        #expect(!names.contains("installed-apps.json"))
        #expect(names.contains("diagnostic-reports/CrosswindHost.ips.txt"))
        for (name, data) in files {
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("/Users/nandan"), "\(name) leaks the home path")
            #expect(!text.contains("nandanvarma"), "\(name) leaks the email")
            #expect(!text.contains("10.1.2.3"), "\(name) leaks an address")
        }
    }
}
