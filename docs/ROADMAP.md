# Roadmap

Status as of 2026-11-26. Open work is tracked as GitHub issues (https://github.com/nandan-varma/crosswind/issues).

## Built (unit-tested; items marked * still need a live-guest or on-screen check)
- VM on Virtualization.framework: direct kernel boot of an Alpine guest (erofs system disk + data disk), lazy start, idle stop, memory ballooning, resource settings, reset.
- Guest compositor (`crosswindd`, Smithay + pixman) streaming damage over vsock; native NSWindow per Linux window; popups; double-buffered surfaces.
- Three-process model: host agent, store, per-app stubs with own Dock tile and icon; XPC handshake + socketpair.
- Flatpak via libflatpak (install/update/uninstall with progress, launch, logs, permissions), Flathub AppStream catalog (86% of apps have aarch64 builds), popularity, store UI (Discover, categories, search, detail, Installed, Updates, permissions editor, Settings, Diagnostics).
- Integrations: clipboard*, audio output + opt-in microphone*, notifications*, dark mode*, open links*, shared folders + native Open/Save dialogs*, XWayland (xwayland-satellite)*, keyboard layouts*, IME*, window management*.
- Safety: guest-hostile-input limits and rate limits, fuzz-style tests (docs/security.md).
- Tooling: `crosswindctl` (status, install, windows, type/click injection, logs, diagnose, compat), diagnostics bundle with redaction, compatibility harness and ratings, signed release export, Sparkle, image installer with verification.

## Done since 2026-10-31
- Live guest verified end to end on this Mac: install, launch, windows, input, X11 apps, Electron (VSCodium), Qt (Kate, KCalc), GTK (Calculator, GIMP), VLC, Audacity. See docs/compat/matrix.md.
- Electron/Chromium apps start (issue 1): the guest's Flatpak system installation was empty, which broke the portal's nested sandboxes.
- X11 windows are attributed to their Flatpak app through the X-Resource extension (issue 2).
- Tray icons (issue 9): StatusNotifierWatcher in the guest, validated icons in the menu bar, clicks sent back. Verified with Telegram. Not yet: dbusmenu menus for apps that do not draw their own.
- Open files from Finder (issue 10), standard stub menus, xdg-activation (raise requests), Konsole/terminal apps, portal frontend fix, detached-launcher apps (issue 19).
- Rosetta spike (issue 11): share, binfmt, `apply_extra` shim and x86_64 installs work; store integration and Electron stability remain.
- Website and docs (crosswind.nandan.fyi) in `site/`.
- Wrappers at install, URL scheme handlers and the microphone source declared (issues 10 and 20 follow-ups); defaults stay a macOS choice.
- VM watchdog: heartbeat, hang detection, forced stop and a Restart item in the menu bar (issue 15).
- Development tooling: `crosswindctl exec` (debug mode only), `scripts/ctl.sh`, `make image DEBUG_TOOLS=1`, docs/DEVELOPMENT.md.

## Next (see issues)
1. Human verification of what only a person at the screen can judge: clipboard, audio, notifications, dark mode, shared folders and file dialogs, window management (issues 5, 6, 7).
2. IME caret position (issue 4) needs an upstream smithay accessor or our own text-input-v3.
3. Drag and drop (issue 8), x86 apps via Rosetta (issue 11).
4. Performance and battery baselines in CI (issue 14).
5. Release: notarization, DMG, appcast, hosted guest image, v0.1.0 (issue 13), after the public beta feature set is complete. Signing runs through `helpers sign` and `asc`.

## Explicit non-goals (v1)
Guest GPU acceleration, webcams, Bluetooth, Mac App Store distribution.
