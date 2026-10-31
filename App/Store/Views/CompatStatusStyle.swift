// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

extension CompatStatus {
    /// SF Symbol for the rating badge.
    var symbol: String {
        switch self {
        case .works: "checkmark.seal.fill"
        case .caveats: "exclamationmark.triangle.fill"
        case .broken: "xmark.octagon.fill"
        case .noArmBuild: "minus.circle"
        case .untested: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .works: .green
        case .caveats: .orange
        case .broken: .red
        case .noArmBuild, .untested: .secondary
        }
    }
}
