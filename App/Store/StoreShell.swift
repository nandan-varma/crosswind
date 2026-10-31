// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// Placeholder shell; replaced by the full store UI.
struct StoreShell: View {
    let model: StoreModel

    var body: some View {
        List(model.popular(limit: 20)) { app in
            HStack {
                Text(app.name)
                Spacer()
                ActionButton(appID: app.id, model: model)
            }
        }
    }
}
