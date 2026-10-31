// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Which agent commands a stub may send. A stub represents one app: it may launch that app and ask the agent to
/// re-read the shared folders. Store and crosswindctl clients are not restricted here.
enum StubCommandPolicy {
    static func allows(_ body: Crosswind_Agent_Command.OneOf_Body?, appID: String) -> Bool {
        switch body {
        case .launchApp(let launch)?: launch.appID == appID
        case .refreshShares?: true
        default: false
        }
    }
}
