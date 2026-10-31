// SPDX-License-Identifier: AGPL-3.0-or-later

/// A long-running guest operation (install, uninstall, update). Created by `GuestControl`.
public actor OperationHandle {
    public nonisolated let id: UInt64
    /// Progress updates in arrival order. Finishes when the operation completes.
    public nonisolated let progress: AsyncStream<Crosswind_Control_Progress>
    private let progressContinuation: AsyncStream<Crosswind_Control_Progress>.Continuation
    private weak var control: GuestControl?
    private var outcome: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    init(id: UInt64, control: GuestControl) {
        self.id = id
        self.control = control
        (progress, progressContinuation) = AsyncStream.makeStream(
            of: Crosswind_Control_Progress.self, bufferingPolicy: .unbounded)
    }

    /// Returns once the guest reports success; throws on failure or cancellation.
    public func result() async throws {
        if let outcome {
            try outcome.get()
            return
        }
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    /// Asks the guest to cancel. The outcome arrives later through `result()`.
    public func cancel() async throws {
        guard let control else { throw GuestControlError.disconnected }
        try await control.cancel(operation: id)
    }

    func deliver(_ progress: Crosswind_Control_Progress) {
        progressContinuation.yield(progress)
    }

    func finish(_ outcome: Result<Void, Error>) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        progressContinuation.finish()
        for waiter in waiters { waiter.resume(with: outcome) }
        waiters.removeAll()
    }
}
