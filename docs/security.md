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
- Send arbitrary display and control protocol messages. Every field is treated as hostile: the agent checks each frame, cursor, window open and call before anything is allocated, stubs check again before drawing, and messages that fail a check are dropped and logged (rate limited, `os.Logger` category `display`). Message size is capped at 64 MiB. Limits are in the table below; `DisplayLimits`, `RectCodec` and `GuestCallGate` in CrosswindKit hold the Swift side, `guest/crosswindd/src/limits.rs` the guest side.
- Spawn many windows or huge frames (resource exhaustion). Capped: windows, surface size and pixels, damage rects per frame, popup depth, and log and notification rates (see the table).
- Spoof window titles/icons to imitate macOS dialogs. Mitigation: guest windows are visibly app windows with the stub's Dock identity; no guest-controlled windows may use system-level window levels except popups attached to a parent. Titles are cut to 1024 bytes and lose control characters, line/paragraph separators and bidi overrides/isolates (U+202A-202E, U+2066-2069, U+200E/F, U+061C), so a title cannot reorder or hide text. Titles are never prefixed or styled, so a guest window cannot add a system-looking element; a title can still say anything in plain text (see open risks).
- Read/write the data disk and anything the user later shares. Shared folders are per-folder grants made in Settings; none exist by default, and a grant can be read-only. Linux apps can read and write everything in a read-write grant. The file chooser shares a single file outside the grants through a staging directory (`Application Support/Crosswind/Staging`), and the host copies changes back to the chosen destination.
- Reach the user's LAN through the NAT. This is the same as any VM; documented as a limitation. (A per-app network toggle is planned via Flatpak permissions.)

### Limits enforced today

Numbers come from the code; "agent" is `AgentCore` (routing, every guest message), "stub" is the per-app `GuestWindow`/`FileChooserHandler`, "guest" is `crosswindd`.

| What the guest controls | Limit | Where enforced |
| --- | --- | --- |
| Windows per app | 32 | agent (`DisplayLimits.admitOpen`) |
| Windows per environment | 128 | agent |
| Window id | must not already be open; reusable after close | agent |
| Popup parent | must be an open window of the same app | agent |
| Popup depth | 8 | agent |
| Surface side | 16384 physical px | agent (`checkFrame`), stub |
| Surface pixels | 64 Mpx (width x height) | agent, stub |
| Surface `scale_120` | 60 to 960 (0.5x to 8x) | agent, stub |
| Damage rects per frame | 256; non-empty; inside the surface (checked in 64-bit) | agent, stub |
| Damage payload | at most the LZ4 worst case for w*h*4 bytes; must decode to exactly w*h*4 bytes (one spare byte detects overlong output) | agent (bound), stub (`RectCodec`) |
| Frame without a window | dropped | agent |
| Cursor | name 64 bytes; side 512 px; pixels exactly w*h*4 | agent |
| Titles | 1024 bytes; control, separator and bidi characters removed | agent, guest (`limits::clean`) |
| App, Flatpak and launch ids | 256 bytes | agent, guest |
| Guest log lines | 200 per second (burst 500); text 4096 bytes; store keeps 5000 lines | agent (`GuestLogStore`), guest (`read_bounded_line`) |
| Guest events and calls buffered | newest 4096 events, newest 256 calls | agent (`GuestControl`) |
| Notifications | 5 per minute per app (tracked for 512 apps); title 256, body 2048 bytes; icon 1 MiB | agent (`GuestCallGate`), guest portal |
| File dialogs | one open per app on the Mac; one at a time in the guest; 64 filters of 256 bytes; 256 names; no `..` or `/` in names | agent, stub, guest |
| Opening a link | `http`, `https`, `mailto` only; 8192 bytes; no whitespace, control or bidi characters | agent (`GuestCallGate`), guest (`open_url`) |
| Clipboard | text 1 MiB, images and HTML 16 MiB (guest copy and host data); offered MIME types 16 of 64 bytes | agent, guest |
| AppStream catalog (Flathub) | 256 MiB inflated, streamed; bad headers and truncated streams are errors | host (`AppStreamParser`) |
| Host to guest: output | surface and scale limits above; refresh clamped to `i32` | guest (`output_mode`) |
| Host to guest: configure, input | sizes above 16384 are "client's choice"; non-finite motion or axis values and keycodes over 247 are dropped | guest (`configure_size`, `input_is_sane`), agent (motion) |
| Host to guest: requests | app ids are reverse-DNS characters without a leading `-`; at most 64 launch args of 4096 bytes; at most 16 clipboard MIMEs | guest (`control::validate`) |
| Guest frame message | 64 MiB | agent and guest link (`FramedConnection`, `link.rs`) |

Messages that fail a check are dropped, never crash the process. Logs for refusals are rate limited to a burst of 5, then one per second.

### Open risks (not fixed in this pass)

- **App identity is trusted from the guest.** A guest window carries the Flatpak id that the guest's process tree reports. The agent routes that window to the stub for that id, so a malicious app can open windows under another app's Dock identity. Needs the agent to verify ownership (for example, by launching only through the agent and matching launch ids) before this is closed.
- **Titles are plain text.** A guest window can say "Save changes?" in its title. Titles stay in the window's own title bar, but this is still social-engineering surface. A fix would be a title-bar mark only the host draws (not done).
- **Notification text is plain text** and is shown as a notification from the app's stub. Only the rate and sizes are limited.
- **Display messages are not bounded in count.** The display stream is unbounded: a flooding guest can queue frames (up to 64 MiB each) faster than the agent forwards them. Per-window in-flight limits (acks) are not enforced by the agent. Memory use can spike; the agent does not drop frames to cope.
- **Decode allocations.** A valid 16384x4096 damage rect allocates 256 MiB transiently in the stub. Limits cap the total, not the rate.
- **Guest log and notification flood on the guest side.** Lines from app stdout are bounded per line but not per second in `crosswindd`; the host limits rate.
- **Guest process panics.** Smithay glue in `handlers.rs` still uses `expect` on protocol state that a guest app drives. A misbehaving app can crash `crosswindd`; the host then sees the control and display links end. This is guest-internal, not a host compromise, but it is a denial of service.
- **Fuzzing is seeded random, not coverage guided.** The tests in this pass (`SplitMix64`, xorshift) find panics and invariant breaks but not deep protocol bugs. No libFuzzer or cargo-fuzz target exists yet.
- **Not reviewed in this pass:** shared folders and staging (`SharedFolders`, `Staging`), the image store, the portal settings backend, and the stub's file chooser path handling.
- **Shared fixtures depend on the Mac pasteboard.** `AgentCore` reads the real `NSPasteboard`, so tests see `OfferClipboard` requests; `FakeGuest` skips them, which hides any real clipboard bug from those tests.

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
