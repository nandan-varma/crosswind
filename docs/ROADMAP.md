# Roadmap

Phases follow the project brief. Update this file with every milestone.

## Done
- Phase 0: research (docs/research/).
- Phase 1 (partial): boot spike, Flatpak-in-guest spike, display path spike with latency measurement; ADRs 0001-0007.

## In progress
- Phase 2/3: control channel (Flatpak ops, launch, logs), Swift control client, AppStream catalog parser, app scaffold, host agent/stub process split.

## Next
1. Walking skeleton (v0.1.0): first-run image download + checksum, boot, install one Flatpak, launch it as a native window with a Dock tile.
2. Store UI, compatibility matrix harness, Diagnostics window and `crosswindctl`.
3. Integration: clipboard, file dialogs (portal backend), audio, notifications, URL handlers, shared folders, IME, drag-and-drop, XWayland.
4. Hardening: fuzzing, performance/battery pass, accessibility, notarization, Sparkle.

## Explicit non-goals (v1)
Guest GPU acceleration, webcams, Bluetooth, Mac App Store distribution.
