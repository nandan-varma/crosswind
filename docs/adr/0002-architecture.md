# 0002: Architecture: one Linux VM, a guest compositor, native Mac windows

Date: 2026-10-31. Status: accepted. Evidence: docs/research/spike-results.md, landscape.md, source-review.md.

## Context
Goal: Linux GUI apps as individual native Mac windows (own Dock tile, Cmd-Tab entry), zero setup, first-party quality.

## Options considered
1. Wayland forwarding into a macOS-native compositor (Cocoa-Way + waypipe-darwin). Rejected: 67.6k LOC, vendored patched Smithay, no vsock, waypipe as a subprocess, single maintainer, author states latency is under investigation (source-review.md).
2. RDP RemoteApp (Weston RAIL + FreeRDP client). Rejected: RAIL client support on macOS unverified; WSLg's fast path (VAIL) depends on Hyper-V shared memory.
3. GPU path via vzgpu/Venus. Rejected for v1: 10 days old, tearing and VMM-abort defects (its README).
4. **Guest-side compositor + purpose-built protocol (chosen).** All Wayland/X11 semantics live in Linux where the tooling is mature; the host receives window lifecycle, damage rectangles and sends input. Same shape as Crostini/sommelier and WSLg.

## Decision
- VM: raw Virtualization.framework (ADR 0003), Alpine guest (ADR 0004).
- Guest: `crosswindd`, a Rust Smithay compositor with the pixman (software) renderer, one surface tree per xdg toplevel/popup, XWayland via xwayland-satellite (planned), Flatpak via libflatpak.
- Wire: protobuf over vsock (ADR 0005): display channel (port 5000), control channel (port 5001).
- Host: Swift. Processes (planned split, validated by the in-process prototype first): a background host agent (LaunchAgent) that owns the VM and decodes frames into IOSurfaces shared over XPC; the store app; a generated stub app bundle per installed Linux app so each app has its own Dock tile, Cmd-Tab entry and Launchpad/Spotlight presence (one process cannot have several Dock tiles).

## Evidence (measured on M4, macOS 27.0.1)
- Linux `foot` rendered as a native NSWindow end to end.
- Host-injected key press to next frame: p50 2.7 ms, p95 3.0 ms (software path, excludes display scanout).

## Consequences
- No GPU acceleration in v1: 3D-heavy apps rate "known broken" in the compatibility system. Revisit trigger: Apple ships virtio-gpu 3D for Linux guests, or a Venus path passes our latency/tearing gates on macOS 27.x.
- We own the compositor (about 700 lines now). Its protocol coverage is the product's compatibility ceiling.
- Process split adds XPC plumbing; mitigated by keeping the stub-facing API identical to display.proto.
