// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// What the agent does about an idle Linux environment on one check.
public enum IdleAction: Equatable, Sendable {
    case wait
    /// Balloon the guest down to `IdlePolicy.memoryFloor`.
    case shrink
    /// Stop the VM. The next request boots it again.
    case stop
}

/// Decides when an idle environment shrinks and when it stops. Pure, so the timing rules are testable.
public enum IdlePolicy {
    /// Idle time before the guest gives memory back. Stopping waits for the user's timeout.
    public static let shrinkAfter: Duration = .seconds(120)
    /// Usable guest memory while idle (the balloon target). Small enough that the guest's kernel and agent still run.
    public static let memoryFloor: UInt64 = 1 << 30

    /// The environment is busy while an app runs, a Flatpak operation is in flight, a window is open, or a request
    /// from a client is waiting for the guest.
    public static func isBusy(apps: Int, operations: Int, windows: Int, requests: Int) -> Bool {
        apps > 0 || operations > 0 || windows > 0 || requests > 0
    }

    /// - Parameters:
    ///   - busy: see `isBusy`.
    ///   - idleFor: how long the environment has been idle; nil while it is busy.
    ///   - timeout: the user's idle timeout; nil never stops the environment.
    public static func action(busy: Bool, idleFor: Duration?, timeout: Duration?) -> IdleAction {
        guard !busy, let idleFor else { return .wait }
        if let timeout, idleFor >= timeout { return .stop }
        return idleFor >= shrinkAfter ? .shrink : .wait
    }
}
