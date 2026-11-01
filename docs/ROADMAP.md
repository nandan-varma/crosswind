# Roadmap

Status as of 2026-10-31. Open work is tracked as GitHub issues (https://github.com/nandan-varma/crosswind/issues).

## Built (unit-tested; items marked * still need a live-guest or on-screen check)
- VM on Virtualization.framework: direct kernel boot of an Alpine guest (erofs system disk + data disk), lazy start, idle stop, memory ballooning, resource settings, reset.
- Guest compositor (`crosswindd`, Smithay + pixman) streaming damage over vsock; native NSWindow per Linux window; popups; double-buffered surfaces.
- Three-process model: host agent, store, per-app stubs with own Dock tile and icon; XPC handshake + socketpair.
- Flatpak via libflatpak (install/update/uninstall with progress, launch, logs, permissions), Flathub AppStream catalog (86% of apps have aarch64 builds), popularity, store UI (Discover, categories, search, detail, Installed, Updates, permissions editor, Settings, Diagnostics).
- Integrations: clipboard*, audio output + opt-in microphone*, notifications*, dark mode*, open links*, shared folders + native Open/Save dialogs*, XWayland (xwayland-satellite)*, keyboard layouts*, IME*, window management*.
- Safety: guest-hostile-input limits and rate limits, fuzz-style tests (docs/security.md).
- Tooling: `crosswindctl` (status, install, windows, type/click injection, logs, diagnose, compat), diagnostics bundle with redaction, compatibility harness and ratings, signed release export, Sparkle, image installer with verification.

## Next (see issues)
1. Live verification pass of everything marked * (human test list in the issues).
2. Electron apps (VSCodium), X11 window attribution, remaining compat batch.
3. Drag and drop, tray icons, Finder file-type handlers, x86 apps via Rosetta.
4. Release: notarization, DMG, appcast, hosted guest image, v0.1.0.
5. Performance/battery baselines in CI, crash/hang watchdog.

## Explicit non-goals (v1)
Guest GPU acceleration, webcams, Bluetooth, Mac App Store distribution.
