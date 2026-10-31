// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// An app's icon at `size` points. Picks the smallest remote icon at least twice that size (for
/// Retina), falling back to the largest one offered. `AsyncImage` caches through `URLCache`.
struct AppIconView: View {
    let app: CatalogApp
    var size: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        AsyncImage(url: bestIcon?.url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().interpolation(.high).scaledToFit()
            default:
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: shape)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var bestIcon: CatalogIcon? {
        let sufficient = app.icons
            .filter { CGFloat($0.width) >= size * 2 }
            .min { $0.width < $1.width }
        return sufficient ?? app.icons.max { $0.width < $1.width }
    }
}
