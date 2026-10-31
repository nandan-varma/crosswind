// SPDX-License-Identifier: AGPL-3.0-or-later
import CrosswindKit
import SwiftUI

/// A screenshot chosen for the enlarged sheet.
struct ScreenshotSelection: Identifiable {
    let id: Int
    let screenshot: CatalogScreenshot
}

extension CatalogScreenshot {
    var thumbnailURL: URL? {
        images.first { $0.kind == .thumbnail }?.url ?? images.first?.url
    }

    var sourceURL: URL? {
        images.first { $0.kind == .source }?.url ?? images.first?.url
    }
}

/// A fixed 16:10 frame so the carousel keeps its height while images load.
struct ScreenshotThumbnail: View {
    let screenshot: CatalogScreenshot

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        AsyncImage(url: screenshot.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            default:
                ProgressView()
            }
        }
        .frame(width: 480, height: 300)
        .background(.quaternary, in: shape)
        .clipShape(shape)
    }
}

/// The full-size screenshot, dismissed with Done.
struct ScreenshotSheet: View {
    let screenshot: CatalogScreenshot

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: screenshot.sourceURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(minWidth: 720, minHeight: 450)
            if !screenshot.caption.isEmpty {
                Text(verbatim: screenshot.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .onExitCommand { dismiss() }  // Escape closes the sheet, as well as Return on Done
    }
}
