// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Marks a permission that differs from the app's manifest default.
struct PermissionChangedBadge: View {
    var body: some View {
        Text("Changed")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
            .accessibilityHidden(true)
    }
}

/// Warns that a permission reaches far beyond the app.
struct PermissionBroadWarning: View {
    var body: some View {
        Label(
            "Broad access. The app can read and change many files or devices.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}
