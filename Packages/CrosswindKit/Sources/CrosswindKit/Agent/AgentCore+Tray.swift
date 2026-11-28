// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Tray icons for `AgentCore`: guest events become `TrayChange`s for the presenter, clicks go back to the guest.
extension AgentCore {
    /// A tray icon event from the guest, or nil for any other event or a malformed icon.
    func trayChange(from event: Crosswind_Control_Event) -> TrayChange? {
        switch event.body {
        case .trayItemChanged(let message)?: TrayItem(message).map(TrayChange.changed)
        case .trayItemRemoved(let message)?: .removed(id: message.id)
        default: nil
        }
    }

    func publish(tray change: TrayChange) {
        switch change {
        case .changed(let item): trayIDs.insert(item.id)
        case .removed(let id): trayIDs.remove(id)
        }
        onTray?(change)
    }

    /// Forwards a click on a tray icon in the menu bar to the guest app that owns it.
    public func trayClicked(id: String, kind: Crosswind_Control_TrayActivate.Kind, x: Int32, y: Int32) {
        guard trayIDs.contains(id) else { return }
        let activate = Crosswind_Control_TrayActivate.with {
            $0.id = id
            $0.kind = kind
            $0.x = x
            $0.y = y
        }
        Task { _ = try? await request(.trayActivate(activate)) }
    }

    /// Forwards a choice in a tray icon's menu to the guest app that owns it.
    public func trayMenuChosen(id: String, item: Int32) {
        guard trayIDs.contains(id) else { return }
        Task {
            _ = try? await request(
                .trayMenuClick(
                    .with {
                        $0.id = id
                        $0.item = item
                    }))
        }
    }

    /// The guest is gone, so are its tray icons.
    func clearTray() {
        for id in trayIDs { onTray?(.removed(id: id)) }
        trayIDs.removeAll()
    }
}
