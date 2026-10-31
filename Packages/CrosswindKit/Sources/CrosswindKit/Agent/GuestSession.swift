// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Where the agent keeps the guest image and the user's data disk.
public struct GuestPaths: Sendable {
    public let supportDirectory: URL
    public var imageDirectory: URL { supportDirectory.appending(path: "Image", directoryHint: .isDirectory) }
    public var dataDisk: URL { supportDirectory.appending(path: "data.img") }

    public init(supportDirectory: URL) { self.supportDirectory = supportDirectory }

    public static var standard: GuestPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return GuestPaths(supportDirectory: base.appending(path: "Crosswind", directoryHint: .isDirectory))
    }
}

/// The running guest: VM lifecycle plus its two channels. Everything above the agent sees only `State` changes.
@MainActor
public final class GuestSession {
    public private(set) var state = Crosswind_Agent_State() {
        didSet {
            onStateChange?(state)
            stateContinuation.yield(state)
        }
    }
    public var onStateChange: ((Crosswind_Agent_State) -> Void)?
    /// Every change to `state`, as a stream for a second observer alongside `onStateChange`. Keeps only the latest.
    public let states: AsyncStream<Crosswind_Agent_State>
    private let stateContinuation: AsyncStream<Crosswind_Agent_State>.Continuation
    public var onDisplay: ((DisplayConnection) -> Void)?
    public var onControl: ((ControlConnection) -> Void)?
    /// Called once the control channel is up, before the session reports `running`; lets the agent greet the guest.
    public var onReady: (() async throws -> Void)?

    private let paths: GuestPaths
    private var vm: GuestVM?
    private var starting: Task<Void, Error>?

    public init(paths: GuestPaths) {
        self.paths = paths
        let (stream, continuation) = AsyncStream<Crosswind_Agent_State>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        states = stream
        stateContinuation = continuation
    }

    /// Boots the VM if it is not running and returns once the control channel is up.
    public func ensureRunning() async throws {
        if let starting { return try await starting.value }
        if state.phase == .running { return }
        let task = Task { try await self.boot() }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    public func stop() async {
        guard let vm else { return }
        setPhase(.stopping)
        try? await vm.stop()
        self.vm = nil
        setPhase(.stopped)
    }

    private func boot() async throws {
        setPhase(.starting, detail: "Starting the Linux environment")
        let vm = GuestVM(imageDirectory: paths.imageDirectory, dataDisk: paths.dataDisk)
        self.vm = vm
        vm.onDisplayConnection = { [weak self] connection in self?.onDisplay?(connection) }

        let controlReady = AsyncStream<ControlConnection>.makeStream(bufferingPolicy: .bufferingNewest(1))
        vm.onControlConnection = { [weak self] connection in
            self?.onControl?(connection)
            controlReady.continuation.yield(connection)
        }
        do {
            try await vm.start()
            var connected = false
            for await _ in controlReady.stream {
                connected = true
                break
            }
            guard connected else { throw GuestSessionError.noControlChannel }
            try await onReady?()
            setPhase(.running)
        } catch {
            self.vm = nil
            setPhase(.failed, detail: error.localizedDescription)
            throw error
        }
    }

    /// Tracks which apps run in the guest from control events.
    func apply(_ event: Crosswind_Control_Event) {
        switch event.body {
        case .appStarted(let started)?:
            if !state.runningApps.contains(started.appID) { state.runningApps = (state.runningApps + [started.appID]).sorted() }
        case .appExited(let exited)?:
            state.runningApps.removeAll { $0 == exited.appID }
        default:
            break
        }
    }

    /// The control stream ending means the guest is gone (crash, shutdown).
    func guestEnded() {
        guard state.phase == .running else { return }
        vm = nil
        state.runningApps = []
        setPhase(.failed, detail: "The Linux environment stopped unexpectedly")
    }

    private func setPhase(_ phase: Crosswind_Agent_VmPhase, detail: String = "") {
        state.phase = phase
        state.detail = detail
    }
}

public enum GuestSessionError: Error {
    case noControlChannel
    case guest(String)
}
