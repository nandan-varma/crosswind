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

    /// Windows the display path has open. AgentCore keeps it current.
    var openWindowCount = 0
    /// Client requests waiting for the guest. AgentCore keeps it current.
    var requestsInFlight = 0
    /// Flatpak operations (install, update, uninstall) in flight, from guest Progress and OperationDone events.
    private var operations: Set<UInt64> = []
    private var idleSince: ContinuousClock.Instant?
    private var ballooned = false
    private var monitor: Task<Void, Never>?

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

    /// Reloads the shared folders from disk and applies them to the running VM. A VM that boots later builds its
    /// configuration from the same file, so nothing happens when no VM runs.
    public func applySharedFolders() throws {
        guard let vm else { return }
        try FileManager.default.createDirectory(at: Staging.root, withIntermediateDirectories: true)
        vm.updateSharedFolders(try SharedFolders.load(from: SharedFolders.defaultFile))
    }

    public func stop() async {
        guard let vm else { return }
        setPhase(.stopping)
        try? await vm.stop()
        self.vm = nil
        tearDown()
        setPhase(.stopped)
    }

    /// Stops the VM and starts it again, so changed resource settings take effect.
    public func restart() async throws {
        await stop()
        try await ensureRunning()
    }

    /// Stops the VM and deletes the data disk. Every installed app and its data are lost; the next start makes a new
    /// disk.
    public func resetDataDisk() async throws {
        await stop()
        guard FileManager.default.fileExists(atPath: paths.dataDisk.path) else { return }
        try FileManager.default.removeItem(at: paths.dataDisk)
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
            idleSince = .now
            startMonitor()
        } catch {
            self.vm = nil
            setPhase(.failed, detail: error.localizedDescription)
            throw error
        }
    }

    /// Tracks which apps run in the guest, and which Flatpak operations are in flight, from control events.
    func apply(_ event: Crosswind_Control_Event) {
        switch event.body {
        case .appStarted(let started)?:
            if !state.runningApps.contains(started.appID) {
                state.runningApps = (state.runningApps + [started.appID]).sorted()
            }
            restoreMemory()
        case .appExited(let exited)?:
            state.runningApps.removeAll { $0 == exited.appID }
        case .progress(let progress)?:
            operations.insert(progress.operation)
        case .operationDone(let done)?:
            operations.remove(done.operation)
        default:
            break
        }
    }

    /// The control stream ending means the guest is gone (crash, shutdown).
    func guestEnded() {
        guard state.phase == .running else { return }
        vm = nil
        tearDown()
        setPhase(.failed, detail: "The Linux environment stopped unexpectedly")
    }

    // MARK: Idle

    private func startMonitor() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.checkIdle()
            }
        }
    }

    /// Applies `IdlePolicy` once: gives memory back after a short idle spell, stops the VM after the user's timeout.
    private func checkIdle() {
        guard state.phase == .running else { return }
        let busy = IdlePolicy.isBusy(
            apps: state.runningApps.count, operations: operations.count, windows: openWindowCount,
            requests: requestsInFlight)
        guard !busy else {
            idleSince = nil
            restoreMemory()
            return
        }
        let now = ContinuousClock.now
        let since = idleSince ?? now
        idleSince = since
        switch IdlePolicy.action(busy: false, idleFor: now - since, timeout: Preferences.idleTimeout) {
        case .wait:
            break
        case .shrink:
            guard !ballooned else { return }
            ballooned = true
            vm?.setMemoryTarget(IdlePolicy.memoryFloor)
        case .stop:
            Task { await self.stop() }
        }
    }

    private func restoreMemory() {
        guard ballooned else { return }
        ballooned = false
        vm?.setMemoryTarget(nil)
    }

    private func tearDown() {
        monitor?.cancel()
        monitor = nil
        operations.removeAll()
        idleSince = nil
        ballooned = false
        state.runningApps = []
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
