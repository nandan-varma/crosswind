# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Store design: Discover's hero takes its gradient from the app's own icon and has a page indicator; Liquid Glass buttons and badges; cards lift under the pointer; icons get a hairline and soft shadow; the sidebar's category icons carry their own colors; button state changes animate.
- Website redesign: glass header, real store screenshot in a window frame, bento feature grid, gallery of real Linux apps, light and dark themes, reduced-motion support, previous/next and edit links in the docs.

### Added
- Website and documentation at https://crosswind.nandan.fyi (Astro, in `site/`, published with Wrangler to Cloudflare).
- Settings: Rosetta toggle (with install button), tray icons toggle, automatic update checks and downloads.
- Experimental Rosetta support in the guest: the Rosetta share is mounted and registered for x86_64 binaries, and Flatpak `apply_extra` works under it (see docs/KNOWLEDGE.md). Intel-only apps are not offered in the store yet.
- Open files from Finder: "Open With" and drops on an app's Dock tile open files in the Linux app (types come from the catalog); files outside granted folders are cloned into the staging share.
- Standard Mac menus (About, Hide, Quit, Window) in every app stub.
- Tray icons: apps' StatusNotifier icons appear in the Mac menu bar; left, middle and right clicks reach the app (the app shows its own context menu).
- VM watchdog: the agent heartbeats the guest, force-stops a hung VM and offers Restart in the menu bar.
- `crosswindctl exec` runs a command in the guest (debug mode only), `scripts/ctl.sh`, `make image DEBUG_TOOLS=1`.
- docs/DEVELOPMENT.md.
- The guest daemon logs to `/run/crosswind/crosswindd.log` (debug level in debug mode); read it with `crosswindctl exec`.

### Fixed
- Folders and files chosen in an app's Open dialog did not open: a newly granted folder was saved but the running VM was never told, and with the Rosetta device present the live update could target the wrong virtiofs device. The file chooser now refreshes the shares after any grant, and the device is found by its tag.
- Copying in a Linux app never reached the Mac clipboard: the guest read the selection before smithay had installed it. It now reads once the loop iteration is done.
- Modifier keys could stay stuck in the guest (Cmd-Tab away with Command held), and synthetic key events with modifiers lost them. The view now reconciles the guest's modifiers with every key event and releases them all when the window stops being key.
- Stubs are registered with LaunchServices after they are written, so their icons and file types show immediately.
- Portal frontend ran without our backend (dark mode, file dialogs and notifications did nothing in apps): the session bus now carries `XDG_CURRENT_DESKTOP`, so whichever process starts the frontend, it picks our backend.
- Kate's (and any Konsole-based) Terminal crashed the app: the guest lacked `getent`, which Flatpak host commands use to find the user's shell, and the guest user's shell was `nologin`.
- Apps that ask to be raised (Telegram's tray toggle, notification clicks) now are: xdg-activation is forwarded to the Mac window.
- Launchers that hand off to a detached main process (VS Code) no longer end their stub and Dock tile while the app runs; an app counts as running while its Flatpak instance has processes.
- Apps whose AppStream id carries a `.desktop` suffix (Kate and other KDE apps) now match their Flatpak id, so they get icons and installed state.
- Stubs created without an icon get one the next time they are opened.
- Electron and other Chromium apps hung at startup without a window: the guest's Flatpak system installation was not initialized.
- X11 apps (VLC, Audacity, GIMP) had windows without a Flatpak id and never appeared in their stub.
- Cancelling an input-method composition (empty marked text) committed the pending text.
- `XDG_SESSION_TYPE` is set to `wayland` so launchers choose Wayland; the guest resolves its own hostname.

### Added
- First end-to-end build: Linux apps from Flathub run as native Mac windows with their own Dock tiles (see docs/ROADMAP.md for what is verified and what is open).

### Added

- XcodeGen project (`project.yml`) with the `Crosswind` app, the `crosswindctl` tool and the `CrosswindTests` unit tests.
- Placeholder store shell (Discover, Installed, Updates) in the app.
- `crosswindctl status` stub.
- `Makefile` with build, test, lint, format, proto, guest and image targets.
- SwiftLint and `swift-format` configuration.
- GitHub Actions CI for the macOS app and the Linux arm64 guest.
