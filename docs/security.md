# Security and threat model

Status: draft, updated as features land. Facts come from the code in this repository; statements about macOS behavior are marked (verify) until tested.

## Assets
- The user's Mac files, credentials, clipboard, microphone and network position.
- The integrity of the guest image and app catalog (what the user installs and runs).
- Privacy: no telemetry, no crash upload unless the user opts in.

## Trust boundaries
1. **Host <-> guest VM.** The guest is untrusted. It sees: a virtio NAT network, a read-only system disk, its own data disk, and two vsock channels. Nothing else is attached: no shared folders, no audio, no USB until the user grants them explicitly (planned features, each with its own prompt).
2. **Host processes.** Store app, host agent, per-app stubs (planned split). They talk over XPC; the agent only accepts connections from code-signed Crosswind binaries or registered stubs.
3. **Network.** Flatpak downloads go over TLS and are verified by OSTree commit signatures against the pinned Flathub key. Catalog XML is delivered through Flatpak's verified path. Flathub JSON (popularity, sizes) is display-only.
4. **Updates.** App updates are delivered by Sparkle with EdDSA signatures plus Developer ID code signing (planned). Guest image updates are verified by SHA-256 pinned in the signed app release metadata (planned).

## Guest compromise (main threat)
A malicious Linux app (or a Flatpak escape) controls the guest. What it can do to the host today:
- Send arbitrary display and control protocol messages. The host decoder must treat every field as hostile: bounds-check sizes, damage rectangles and compressed lengths (implemented: frames are decoded into fixed-size IOSurfaces after size checks; message size is capped at 64 MiB). **Open work:** fuzz the Swift decoder and the Rust request parser.
- Spawn many windows or huge frames (resource exhaustion). **Open work:** caps on window count and surface size per app.
- Spoof window titles/icons to imitate macOS dialogs. Mitigation: guest windows are visibly app windows with the stub's Dock identity; no guest-controlled windows may use system-level window levels except popups attached to a parent.
- Read/write the data disk and anything the user later shares. Shared folders are per-folder grants made in Settings; none exist by default, and a grant can be read-only. Linux apps can read and write everything in a read-write grant. The file chooser shares a single file outside the grants through a staging directory (`Application Support/Crosswind/Staging`), and the host copies changes back to the chosen destination.
- Reach the user's LAN through the NAT. This is the same as any VM; documented as a limitation. (A per-app network toggle is planned via Flatpak permissions.)

## Host-side privileges
- Entitlements: `com.apple.security.virtualization` only. No sandbox (required for LaunchAgent, generated app stubs and VM disk access; verify the sandbox alternative before release).
- Hardened runtime on, notarized, Developer ID signed. Generated per-app stubs are ad-hoc signed locally on the user's machine.
- TCC prompts (microphone, camera) are triggered only when the corresponding device is enabled and used.

## Supply chain
- Rust dependencies pinned by Cargo.lock; Swift by Package.resolved; Alpine packages pinned to a release branch. `docs/dependencies.md` lists each dependency, its license and replacement plan.
- The guest image is built in CI from this repository; releases publish SHA256SUMS.

## Not covered / known limitations
- No protection against a compromised host OS.
- Side channels between guest and host (timing, memory pressure) are out of scope.
- Clipboard: text and images are shared only while a Crosswind app is frontmost (the Mac offers MIME types; data is sent only when the guest pastes). Guest copies are written to the Mac clipboard. Settings > General can turn it off. Drag-and-drop, once added, can exfiltrate or inject content and will be user-visible and per-app opt-in.
