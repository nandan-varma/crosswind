// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// The standard Mac menus for a Linux app's stub: application (About, Hide, Quit) and Window (Minimize, Zoom). Edit
/// and the other app-specific menus are deliberately absent: the Linux app draws its own, and Cmd-C, Cmd-V and the
/// rest reach it as keys.
@MainActor
enum StubMenu {
    static func install(appName: String) {
        let main = NSMenu()
        main.addItem(submenu(applicationMenu(appName)))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func applicationMenu(_ appName: String) -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(
            withTitle: String(localized: "About \(appName)"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Hide \(appName)"), action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        let others = menu.addItem(
            withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit \(appName)"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(
            withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        menu.addItem(
            withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Bring All to Front"), action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "")
        return menu
    }
}
