# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

First public beta (0.1.0).

### Apps
- Browse, search, install, update and remove Flathub apps in a built-in store, with a permissions editor.
- GTK, Qt, Electron and X11 apps run as native Mac windows, each with its own Dock icon, Cmd-Tab entry and standard
  Mac menus. Tested apps are listed in `docs/compat/matrix.md`.
- Every installed app gets its Mac wrapper at install time, so it appears in Spotlight, Launchpad and Finder's Open
  With. Default apps for file types stay a macOS choice (Get Info > Open with > Change All).
- Open files from Finder (Open With, drops on the Dock icon) and open links such as `tg://` and `magnet:` in the
  Linux app that handles them.

### Integration
- Clipboard in both directions (text, images, HTML), dark mode, notifications, links that open in your Mac browser,
  native Open and Save dialogs, shared folders, audio output, keyboard layouts and input methods.
- Drag and drop between Mac and Linux apps: text and files, both ways. Dropped Mac files are shared like files opened
  from Finder; a Linux drag that leaves the app's windows becomes a Mac drag (text, and files inside shared folders).
- Tray icons appear in the menu bar and clicks reach the app. Apps can ask to be raised.
- Window title bars take the color of the app's own header bar.

### Environment
- A small Linux VM (Virtualization.framework) that starts on demand, gives memory back when idle and stops after a
  while. A watchdog restarts a hung environment, with a Restart item in the menu bar.
- Settings for CPUs, memory, idle timeout, shared folders, tray icons, microphone, Rosetta (experimental) and updates.
- Experimental Intel-app support through Rosetta at the guest level; Intel-only apps are not offered in the store yet.

### First run and design
- Onboarding: welcome, guided approval of the background service, setup progress, and starter apps.
- App icon, menu bar glyph, an icon-tinted Discover hero, Liquid Glass buttons and colored sidebar icons.
- Help menu with documentation, compatibility, release notes and issue links.

### Distribution
- Developer ID signed and notarized DMG, Sparkle updates, guest image verified by SHA-256.
- Website and documentation at https://crosswind.nandan.fyi (Astro, in `site/`).

### Development
- `crosswindctl` (status, install, windows, input injection, logs, diagnostics, compatibility harness) and, in debug
  mode only, `crosswindctl exec` to run commands in the guest. See `docs/DEVELOPMENT.md`.
