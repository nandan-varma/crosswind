# Public beta checklist

Run on a clean Mac account (or after wiping Crosswind: see "Reset" below) with the notarized DMG, not a dev build.

## Install and first run
- [ ] Open the DMG, drag Crosswind to Applications, open it. Gatekeeper opens it without a warning.
- [ ] The welcome screen appears and macOS has asked for nothing yet.
- [ ] Continue opens the background-item step; turning Crosswind on in Login Items advances by itself.
- [ ] Setup shows real progress and tips, then "You're all set" with starter apps.
- [ ] Installing a starter app from that screen works; Start Exploring opens the store.

## Apps
- [ ] Install, open, quit and uninstall one GTK app (Text Editor), one Qt app (Kate), one Electron app (VSCodium).
- [ ] Each app has its own Dock icon, menus (About, Hide, Quit) and Cmd-Tab entry.
- [ ] Cmd-C / Cmd-V work in both directions between Mac and Linux apps.
- [ ] Open a file from Finder with Open With; open a folder from VSCodium's Open Folder.
- [ ] Dark and light mode follow the system. A notification appears (macOS asks for permission once).
- [ ] A tray icon (Telegram) appears in the menu bar and its click shows or hides the window.
- [ ] Sound plays (VLC with a media file). With the microphone on in Settings, an app (Audacity) sees an input device.
- [ ] Right-click a tray icon that exports a menu (Telegram after login): a native menu appears and its entries work.
- [ ] Drag text and a file from a Mac app onto a Linux editor (Kate); drag selected text and a shared-folder file out of a Linux app onto the Mac.
- [ ] A second macOS keyboard layout and an input method (Pinyin, Kana) type the right characters; the candidate window opens at the caret.
- [ ] An Intel-only app (Zoom) shows an "Intel app" notice, installs and opens (Rosetta on).
- [ ] With the network off, an install fails with a message about reaching Flathub, and Retry works once it is back.

## Environment
- [ ] Settings: every control works; Restart Environment and Reset Linux Environment behave.
- [ ] Quit the host from its menu bar item and open an app: the environment starts again.
- [ ] Check for Updates reports "up to date" once the appcast is published.

## Reset (to repeat a first run)
Quit Crosswind and its host, then remove `/Applications/Crosswind.app`, `~/Applications/Crosswind`,
`~/Library/Application Support/Crosswind`, `~/Library/Caches/dev.crosswind.app`, and delete the `dev.crosswind.*`
preferences (`defaults delete dev.crosswind.shared`, `dev.crosswind.app`).
