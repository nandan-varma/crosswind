// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One tray icon a guest app shows, validated. The guest is untrusted: every field is bounded before it reaches the
/// menu bar (see docs/security.md).
public struct TrayItem: Equatable, Sendable, Identifiable {
    public struct Icon: Equatable, Sendable {
        public let width: Int
        public let height: Int
        /// Straight (non-premultiplied) RGBA, `width * height * 4` bytes.
        public let rgba: Data
    }

    public static let maxIconSide = 256
    public static let maxIDBytes = 512
    public static let maxTitleBytes = 1024

    public let id: String
    public let title: String
    /// Nil when the app only names a themed icon; the presenter then falls back to the app's own icon.
    public let icon: Icon?
    /// The app asked to hide the icon.
    public let isPassive: Bool

    /// Nil when the message is malformed: an empty or oversized id, or an icon whose size and data disagree.
    public init?(_ message: Crosswind_Control_TrayItemChanged) {
        guard !message.id.isEmpty, message.id.utf8.count <= Self.maxIDBytes else { return nil }
        let width = Int(message.iconWidth)
        let height = Int(message.iconHeight)
        let icon: Icon?
        if message.iconRgba.isEmpty && width == 0 && height == 0 {
            icon = nil
        } else {
            let sides = 1...Self.maxIconSide
            guard sides.contains(width), sides.contains(height), message.iconRgba.count == width * height * 4 else {
                return nil
            }
            icon = Icon(width: width, height: height, rgba: message.iconRgba)
        }
        id = message.id
        var bytes = 0
        title = String(
            message.title.prefix {
                bytes += String($0).utf8.count
                return bytes <= Self.maxTitleBytes
            })
        self.icon = icon
        isPassive = message.passive
    }
}

/// A change to the set of tray icons, for the presenter in the host agent.
public enum TrayChange: Equatable, Sendable {
    case changed(TrayItem)
    case removed(id: String)
}
