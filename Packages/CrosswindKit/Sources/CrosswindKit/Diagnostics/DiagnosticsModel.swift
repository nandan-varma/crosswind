// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Foundation
import Observation

/// Per-window numbers for the HUD. `framesPerSecond` comes from the frame counter delta between two polls.
public struct WindowStats: Identifiable, Sendable, Equatable {
    public var id: UInt32 { info.id }
    public var info: WindowRecord
    public var framesPerSecond: Double
    /// Latest input-to-frame latencies, oldest first.
    public var latencyHistory: [Double]
}

public struct ProcessReadout: Sendable, Equatable {
    public var residentBytes: UInt64
    public var cpuPercent: Double?
}

/// Feeds the Diagnostics window: guest and app log lines, VM phase, window stats and host agent resource use.
@MainActor
@Observable
public final class DiagnosticsModel {
    public static let pollInterval = Duration.seconds(2)
    public static let historyLength = 120
    public static let agentBundleID = "dev.crosswind.host"

    public private(set) var logs = LogRingBuffer()
    public private(set) var phase: Crosswind_Agent_VmPhase = .stopped
    public private(set) var phaseDetail = ""
    public private(set) var runningApps: [String] = []
    /// When the VM last entered `running`; nil while it is not running.
    public private(set) var runningSince: Date?
    public private(set) var windows: [WindowStats] = []
    public private(set) var agentProcess: ProcessReadout?
    public private(set) var isConnected = false
    public private(set) var lastError: String?

    private var agent: AgentClient?
    private var tasks: [Task<Void, Never>] = []
    private var windowsVisible = false
    private var latencyHistory: [UInt32: [Double]] = [:]
    private var previousFrames: [UInt32: (frames: UInt64, at: Date)] = [:]
    private var previousSample: ProcessSample?

    public init() {}

    /// Connects to the host agent as the store app. Safe to call repeatedly.
    public func connect() async {
        guard !isConnected else { return }
        do {
            let client = try await AgentClient.connect(role: .store)
            attach(client)
        } catch {
            lastError = "agent connection failed: \(error.localizedDescription)"
        }
    }

    func attach(_ client: AgentClient) {
        agent = client
        isConnected = true
        tasks.append(Task { [weak self] in
            for await event in client.control.events {
                guard let self else { return }
                self.record(event)
            }
        })
        tasks.append(Task { [weak self] in
            for await state in client.states {
                guard let self else { return }
                self.apply(state)
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollWindows()
                self.sampleProcess()
                try? await Task.sleep(for: Self.pollInterval)
            }
        })
    }

    public func disconnect() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        if let agent { Task { await agent.disconnect() } }
        agent = nil
        isConnected = false
    }

    /// The window HUD polls only while its tab is on screen.
    public func setWindowsVisible(_ visible: Bool) {
        windowsVisible = visible
    }

    /// Runs an agent command for the Actions tab; the resulting state arrives through the state stream.
    public func run(_ body: Crosswind_Agent_Command.OneOf_Body) async {
        guard let agent else {
            lastError = "not connected to the host agent"
            return
        }
        do {
            _ = try await agent.command(body)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// Writes a diagnostic bundle (zip) to `destination`.
    public func exportBundle(to destination: URL) async throws {
        guard let agent else { throw AgentCommandError.disconnected }
        let snapshot = await DiagnosticBundle.collect(agent: agent, guestLogs: Array(logs.entries))
        _ = try DiagnosticBundle.write(snapshot, to: destination)
    }

    /// Appends the host's own unified-log lines (dev.crosswind) to the log buffer.
    public func loadHostLogs() async {
        let result = await Task.detached { HostLogReader.recent(limit: DiagnosticBundle.hostLogLimit) }.value
        for line in result.lines {
            logs.append(source: "host", level: 6, text: line)
        }
        if let note = result.note { lastError = note }
    }

    func record(_ event: GuestControl.Event) {
        switch event {
        case .log(let line):
            logs.append(source: line.source, level: line.level, launchID: line.launchID, text: line.text,
                        time: Date(timeIntervalSince1970: Double(line.unixTimeMs) / 1000))
        case .appStarted(let started):
            logs.append(source: started.appID, level: 6, launchID: started.launchID,
                        text: "started, pid \(started.pid)")
        case .appExited(let exited):
            logs.append(source: exited.appID, level: exited.exitCode == 0 ? 6 : 4, launchID: exited.launchID,
                        text: "exited with code \(exited.exitCode)")
        }
    }

    func apply(_ state: Crosswind_Agent_State) {
        if state.phase == .running, phase != .running { runningSince = Date() }
        if state.phase != .running { runningSince = nil }
        phase = state.phase
        phaseDetail = state.detail
        runningApps = state.runningApps
    }

    private func pollWindows() async {
        guard windowsVisible, let agent else { return }
        guard let result = try? await agent.command(.listWindows(.init())) else { return }
        let now = Date()
        var next: [WindowStats] = []
        for info in result.windows {
            var history = latencyHistory[info.id, default: []]
            history.append(info.lastInputToFrameMs)
            if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
            latencyHistory[info.id] = history
            var fps = 0.0
            if let previous = previousFrames[info.id] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0, info.frames >= previous.frames {
                    fps = Double(info.frames - previous.frames) / elapsed
                }
            }
            previousFrames[info.id] = (info.frames, now)
            next.append(WindowStats(info: WindowRecord(info), framesPerSecond: fps, latencyHistory: history))
        }
        let live = Set(result.windows.map(\.id))
        latencyHistory = latencyHistory.filter { live.contains($0.key) }
        previousFrames = previousFrames.filter { live.contains($0.key) }
        windows = next
    }

    private func sampleProcess() {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.agentBundleID)
            .first?.processIdentifier,
            let sample = ProcessSampler.sample(pid: pid)
        else {
            agentProcess = nil
            previousSample = nil
            return
        }
        let cpu = previousSample.flatMap { ProcessSampler.cpuPercent(from: $0, to: sample) }
        agentProcess = ProcessReadout(residentBytes: sample.residentBytes, cpuPercent: cpu)
        previousSample = sample
    }
}
