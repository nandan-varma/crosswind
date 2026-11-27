// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CrosswindKit

/// Shows each guest app's tray icon as a menu bar item and sends clicks back to the app.
@MainActor
final class TrayController: NSObject {
    private static let iconHeight: CGFloat = 18

    private let activate: (String, Crosswind_Control_TrayActivate.Kind, Int32, Int32) -> Void
    private var statusItems: [String: NSStatusItem] = [:]
    /// Every icon the guest has asked for, shown or not, so turning the setting back on restores them.
    private var items: [String: TrayItem] = [:]

    init(activate: @escaping (String, Crosswind_Control_TrayActivate.Kind, Int32, Int32) -> Void) {
        self.activate = activate
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification,
            object: Preferences.suite)
    }

    func apply(_ change: TrayChange) {
        switch change {
        case .changed(let item): items[item.id] = item
        case .removed(let id): items.removeValue(forKey: id)
        }
        render(change)
    }

    private func render(_ change: TrayChange) {
        switch change {
        case .changed(let item) where Preferences.trayIconsEnabled: show(item)
        case .changed(let item): remove(item.id)
        case .removed(let id): remove(id)
        }
    }

    @objc private func preferencesChanged() {
        for item in items.values { render(.changed(item)) }
    }

    private func show(_ item: TrayItem) {
        guard !item.isPassive else { return remove(item.id) }
        let statusItem =
            statusItems[item.id]
            ?? {
                let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                created.button?.target = self
                created.button?.action = #selector(clicked(_:))
                created.button?.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
                created.button?.identifier = NSUserInterfaceItemIdentifier(item.id)
                statusItems[item.id] = created
                return created
            }()
        statusItem.button?.image = Self.image(for: item)
        statusItem.button?.toolTip = item.title
        statusItem.button?.setAccessibilityLabel(item.title)
    }

    private func remove(_ id: String) {
        guard let statusItem = statusItems.removeValue(forKey: id) else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let event = NSApp.currentEvent else { return }
        let kind: Crosswind_Control_TrayActivate.Kind =
            switch event.type {
            case .rightMouseUp: .contextMenu
            case .otherMouseUp: .secondary
            default: .primary
            }
        let point = sender.window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        activate(id, kind, Int32(point.x), Int32(point.y))
    }

    /// The app's pixels at menu bar height, or a generic symbol when it only names a themed icon.
    private static func image(for item: TrayItem) -> NSImage? {
        guard let icon = item.icon, let image = bitmap(icon) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: item.title)
        }
        image.size = NSSize(width: iconHeight * CGFloat(icon.width) / CGFloat(icon.height), height: iconHeight)
        return image
    }

    private static func bitmap(_ icon: TrayItem.Icon) -> NSImage? {
        guard
            let provider = CGDataProvider(data: icon.rgba as CFData),
            let cgImage = CGImage(
                width: icon.width, height: icon.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: icon.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
