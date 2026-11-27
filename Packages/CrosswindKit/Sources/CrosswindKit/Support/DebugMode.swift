// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Development-only features (running commands in the guest). On only when the process was started with
/// `CROSSWIND_DEBUG=1`, which `scripts/dev-agent.sh` sets and a shipped build never does.
public enum DebugMode {
    public static let isEnabled = ProcessInfo.processInfo.environment["CROSSWIND_DEBUG"] == "1"
}
