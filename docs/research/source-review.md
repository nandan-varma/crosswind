# Source review: cocoa-way, Wawona, waypipe-darwin, vzgpu, upstream waypipe

Date: 2026-10-31. Method: shallow clones into `/tmp/crosswind-src/{cocoa-way,wawona,waypipe-darwin,vzgpu}` plus `waypipe-upstream` (v0.11.3) and `waypipe-upstream-0.11.2` for diffing. Nothing was built or executed. LOC from `cloc` (vendor, third_party and the bundled `weston-13.0.0` tree excluded). Metric counts are `rg` line hits, not parsed AST counts, and include test code unless stated.

---

## Facts

### Upstream waypipe (gitlab.freedesktop.org/mstoeckl/waypipe)

- Reachable via `git ls-remote`. GitHub mirror `talex5/waypipe` returned "Repository not found" and was not used.
- Latest tag by version sort: **v0.11.3** (tag commit `3ea049b`, 2026-10-19). Tags also include v0.11.1, v0.11.2.
- License: **GPL-3.0-or-later** (`Cargo.toml`, `LICENSE`).
- **vsock is supported upstream**: `--vsock` flag, `-s CID:PORT`, documented in `waypipe.scd` (lines 163-164, 260-273) with a host/guest example.
- **macOS is not documented upstream.** Code uses `memfd_create` and `ppoll` (Linux-only). The fork exists to patch this.

### cocoa-way (github.com/J-x-Z/cocoa-way), v2.1.2, 113 commits

- LOC (cloc): 67.6k total. Rust 60.0k, Python 6.1k (scripts), Shell 0.65k, Swift 0.16k, YAML/TOML/MD small.
- License: **GPL-3.0-only** (`Cargo.toml`, `LICENSE`). Application crate, no library target.
- Layout: `src/` is flat, about 90 files. Largest: `container_mode.rs` 14.6k, `main.rs` 7.2k, `container_sessions.rs` 4.6k, `state.rs` 3.7k, `presentation.rs` 1.7k, `control_api.rs` 1.7k, `metal_renderer.rs` 1.4k, `wayland_source.rs` 1.2k. Also `container_mode/`, `bin/` (cocoa-way-mcp, cocoa-wayctl, research MCP), `test-client/` (workspace member), `scripts/` (23 Python audit scripts), `supplychain/policy.toml`.
- Dependencies (`Cargo.toml`): `smithay` 0.7.0 **vendored** at `vendor/smithay` (MIT; pinned to upstream rev `6329f5b`, with 8 backported commits and 3 local patches, tree sha256 pinned in `vendor/sources.toml`). `winit` =0.30.13 (MIT/Apache-2.0), `objc2` / `objc2-app-kit` / `objc2-metal` / `objc2-quartz-core` / `objc2-foundation` =0.2.2 / =0.5.2 (MIT), `block2`, `raw-window-handle`, `toml`/`toml_edit`, `serde`/`serde_json`, `sha2`, `tracing-subscriber`, `log`, `libc`. Dev: `wayland-client` 0.31, `tempfile`. `Cargo.lock`: 206 packages. Vendored `wayland-backend` is patched via `[patch.crates-io]`.
- **Windowing**: winit 0.30 is the window layer (94 `winit::` references). Rootless mode creates **one winit/NSWindow per xdg-toplevel** (`src/main.rs` ~L4428 `create_window` inside the rootless path, `RootlessWindow` in `presentation.rs`, map keyed by `winit::window::WindowId`). Desktop mode uses one compositor window. Container mode builds its own `NSWindow` via `objc2-app-kit` (`container_mode.rs` `ensure_window`, ~13 NSWindow refs). Popups are tracked as smithay `PopupSurface` in `state.rs` (`popups: Vec<PopupSurface>`).
- **Rendering**: `metal_renderer.rs` on `CAMetalLayer` (objc2-quartz-core). Damage-aware SHM uploads per README.
- **Input**: winit events mapped to Linux scancodes in `keymap.rs` (`map_key(event.physical_key)`, `main.rs` ~L3344). Pointer in `pointer_input.rs`. Scroll deltas are NSEvent-derived approximations (code comment, `pointer_input.rs:269`, `main.rs:3744`).
- **Clipboard**: `clipboard_transfer.rs` (886 lines), bidirectional text and PNG (README: up to 64 MiB). NSPasteboard feature is enabled in `objc2-app-kit`.
- **HiDPI**: winit `scale_factor()` drives Retina scaling. `presentation.rs` sends `fractional_scale.set_preferred_scale`.
- **Transport**: does **not** use vsock (no `vsock`/`AF_VSOCK` in `src/`). Remote and container sessions spawn the `waypipe` binary as a subprocess (`connections.rs` L267 `Command::new(&waypipe)` with `ssh` args, L566). Container path uses Apple `container` CLI with `--publish-socket` (README: "Transport V2"). Local Unix sockets are used for the container relay (`container_sessions.rs`, `apple_container_transport.rs`).
- **Network calls**: `apple_update_notice.rs` opens `https://github.com/apple/container/releases/latest` through `NSWorkspace.openURL`, which is a browser hand-off, not a background fetch. `network.rs` is a loopback-only HTTP proxy helper (`parse_loopback_proxy`, refuses non-loopback). No telemetry library found.
- **Tests**: 643 `#[test]` functions in `src/`, plus 11 integration test files in `tests/` (`native_panel_layout`, `render_pipeline`, `smithay_vendor`, etc.). Also `cocoa_way_mcp` and `research_mcp` test dirs.
- **Code hygiene**: `unsafe` on 727 lines in `src/`. `.unwrap()/.expect(/panic!` about 1,549 hits in `src/` (includes tests; `.unwrap()` alone about 1,479). TODO/FIXME: 1.
- Supply chain: `supplychain/policy.toml` with cargo-audit exceptions for `cgmath` (RUSTSEC-2026-0196, -0197, both unmaintained/unsound, accepted with expiry 2027-01-15). Explicit review records.

### Wawona (github.com/Wawona/Wawona), version 26.10.26, shallow (1 commit)

- LOC (cloc, excluding vendor/weston): 243k total. Rust 63.0k, Swift 47.9k, Markdown 24.9k, C 23.8k, HTML 20.8k, Kotlin 14.5k, Nix 12.9k, shell 12.1k.
- License: **MIT** (`LICENSE`, Alex Spaulding). `NOTICE.example` lists uniffi (MPL-2.0), libssh2 (BSD-3), OpenSSL 3.x (Apache-2.0), etc.
- Layout: `src/` (`core/` with `state/`, `surface/`, `render/`, `window/`, `input/`; `platform/` with `android`, `ios`, `macos`, `watchos`, `modeb`; `linux/`; `ffi/`; `term/`; `darwin_cli/`; `domain/`; `config/`), `Sources/` (SwiftPM: `WawonaApple`, `WawonaModel`, `WawonaUI`, `WawonaUIContracts`, `WawonaWatch`), `Darwin/`, `android/`, `fastlane/`, `Tests/`, `verification/`, `fuzz/`, `dependencies/` (Nix), `contracts/`, `docs/` (very large).
- Dependencies (`Cargo.toml`): `smithay` 0.7 (crates.io, MIT), `wayland-server/client/backend/protocols` 0.31/0.32, `xkbcommon` 0.8, `ash` 0.38 (Vulkan), `libloading`, `nix` 0.30, `uniffi` 0.30 (MPL-2.0), `clap`, `serde`, `anyhow`, `thiserror`, `tracing`, `chrono`, `flate2`, `png`, `ssh2` 0.9 (optional), `coreutils` (uutils, path dep, optional), `gtk4`/`libadwaita` (optional), and **`waypipe` as a path dependency** (`./waypipe`, `default-features = false`, features `lz4`, `zstd`, `video`). `waypipe` is GPL-3.0-or-later. `Cargo.lock` has 486 packages.
- `deny.toml` license allow-list: Apache-2.0, BSD-2/3, BSL-1.0, CDLA-Permissive-2.0, ISC, MIT, MPL-2.0, OpenSSL, Unicode, Zlib. **GPL is not allowed**, yet `waypipe` is linked into the static library when the feature is on.
- **Windowing**: Smithay-based core (`src/core/state/windows.rs`, `pointer_focus.rs`). macOS presentation is SwiftUI/AppKit: `WWNSessionWindowPresenter.swift` creates `NSWindow(contentViewController:)` per session (25 NSWindow refs across `Sources/`). Whether every xdg-toplevel gets its own NSWindow was not confirmed (presenter may host multiple surfaces). Renderer path uses IOSurface and ANGLE per `Cargo.toml` comments (not traced in detail).
- **Input, clipboard, HiDPI**: `src/core/state/input.rs` (Smithay seat), `NSPasteboard` referenced in `Sources/WawonaUI/Settings/*` and machine editor (UI text fields, not Wayland clipboard bridge; the Wayland data-device bridge was not located). `backingScaleFactor` appears in `Sources/WawonaApple/Present/CompositorHostView.swift`.
- **Popups**: not traced.
- **vsock**: none found in `src/` or `Sources/`. Transport is SSH (ssh2) and the bundled waypipe.
- **Network calls**: `src/linux/wasm_launch.rs` L12-13 hard-codes `https://repo.wawona.io/wasm/v1/index.json` as a runtime catalog. This is a runtime fetch from a Wawona-owned host. No telemetry/analytics SDK found (grep for Sentry, PostHog, Mixpanel, Firebase, Crashlytics: none).
- **iland Mode B (alarming)**: `Cargo.toml` L172-173 defines feature `iland-baremetal` described as "Dobby code injection, AMFI bypass, framebufferd/SkyLight, inputd, symrez. macOS-ONLY... requires SIP off + root + private entitlements". `Sources/WawonaApple/ModeB/SipStatus.swift` L104-111 documents `DYLD_INSERT_LIBRARIES` injection of `libwayland-mac.dylib` into WindowServer. `iland` appears 104 times in `src/`. Default builds use "iland Mode A" (in-window), and the README/docs claim App Store compliance. Opt-in feature, but the code is in-tree.
- **Code hygiene**: `unsafe` on 265 lines. `unwrap/expect/panic!` about 406 hits. TODO/FIXME: 9. Rust test functions: 382 (`src/`), plus Swift tests in `Tests/WawonaModelSettingsTests`, `WawonaUIContractsTests`, and an appium directory.
- Also: `docs/ios-local-shell/*` describes a bundled on-device zsh and a `uutils` coreutils set, "App Store-compliant". Not evaluated beyond docs.

### waypipe-darwin (github.com/J-x-Z/waypipe-darwin), v0.11.2 base, 838 commits (mostly upstream history)

- LOC (cloc): 63.1k total. Rust 34.6k (`src/` 39.2k lines incl. generated `wayland_gen.rs` 7.2k), C 15.1k (`waypipe-c/`, the older C implementation still in tree), XML 9.6k (protocols), Python 1.6k (`protogen.py`, tests), Meson, headers.
- License: **GPL-3.0-or-later** (`Cargo.toml`); both `LICENSE.GPLv3` and `LICENSE.MIT` present (MIT for parts from the original project author).
- **Diff vs upstream v0.11.2 (src/ only)**: 9 files changed, +335 / -155 lines (`diff -ru`, 476 changed lines). Darwin changes: no `memfd_create` (unlinks a securely created temp file, `util.rs` ~L1245); `poll` instead of `ppoll` with SIGINT/SIGCHLD handling (`main.rs` ~L773, L817, `util.rs` ~L1348); `video.rs`/`dmabuf.rs`/`gbm.rs` changed to fit macOS. `Cargo.toml` still reports 0.11.2, so the fork lags upstream v0.11.3.
- Build: README says `cargo build --release --locked --no-default-features --features lz4,zstd`. Default features include `video`, `dmabuf` (ash), `gbmfallback`.
- Distribution: Homebrew tap `J-x-Z/tap`, formula `waypipe-darwin.rb`.
- Usage: `waypipe ssh user@host app` (ssh wrapper with reverse tunnel). vsock: `VSockConfig` in `src/main.rs` L184-195 (inherited from upstream).
- `unsafe` on 191 lines in `src/`. `unwrap/panic/expect` about 773 hits. TODO/FIXME 128 across `src` and `waypipe-c` (mostly inherited).
- Tests: 14 `#[test]` functions, plus `tests/proto.rs`.

### vzgpu (github.com/Quiet-Wolfe/vzgpu), 35 commits

- LOC (cloc): 8.5k total. Objective-C 2.6k (`vzgpu.m` 952, `crossdomain.m`, `compositor/src/mac.m`, `tools/vzgpu-tool.m`), Rust 1.4k (`compositor/src/`: `main.rs`, `comp.rs`, `handoff.rs`, `mac.rs`), shell and patches (`guest/*.patch` about 1.6k), `evidence/` logs and PNGs.
- License: **MIT** (`LICENSE`). Third-party notices in `THIRD_PARTY_NOTICES.md` (sommelier BSD-3-Clause, virglrenderer, Mesa, libepoxy, libxkbcommon, Linux GPL-2.0 config, vulkan-loader, etc.). Entitlement: `com.apple.security.virtualization` only (`vzgpu.entitlements`).
- Layout: `vzgpu.m` (VMM host), `crossdomain.{h,m}` (virtio cross-domain context, ported from rutabaga_gfx), `compositor/` (Rust Smithay-based compositor "vzcomp" with Objective-C AppKit bridge `mac.m`), `guest/` (install scripts, systemd units, sommelier patches, Steam fetch, Rosetta test), `kernel/` (Fedora-based kernel build), `tools/` (`vzgpu` CLI, `gssh`, `gsh`, `run-vm`, `package-app.sh`), `third_party/` (licences, `fetch-virglrenderer.sh`, patch).
- Compositor deps: `smithay` path dep at `third_party/smithay`, which is **not vendored**: `compositor/fetch-smithay.sh` clones `github.com/Smithay/smithay` at pinned rev `023b78b1c5a0` and applies `smithay-macos.patch`. Plus `libc`, `cc` (build). Smithay is MIT.
- **Virtualization.framework use**: `VZVirtualMachine`, `VZVirtualMachineConfiguration`, `VZCustomVirtioDevice` / `VZCustomVirtioDeviceConfiguration` (the macOS 27 custom virtio API), `VZVirtioSharedMemoryRegion` (host-visible 8 GiB SHM, 16 KiB alignment), `VZVirtioFileSystemDeviceConfiguration`, `VZLinuxRosettaDirectoryShare`. `VZWindow`, `VZView`, `VZWindowCtl` (NSWindow per window handle in `compositor/src/mac.m`).
- **vsock**: **no vsock in the source.** The commit "Launcher handoff: one Dock tile per Linux app; vsock SSH" describes vsock, but `tools/gssh` SSHes to the guest over vmnet DHCP leases (`/var/db/dhcpd_leases`, fixed MAC). Guest/host IPC is AF_UNIX: `vzgpu.m` L746 listens on a Unix socket, `crossdomain.m` L283-288 connects to one, and `compositor/src/main.rs` L43 and `handoff.rs` L39 bind Unix listeners.
- **Windowing**: NSWindow per Wayland toplevel (`compositor/src/mac.m`, `VZWindowCtl : NSObject <NSWindowDelegate>`, `VZWindow : NSWindow`). `comp.rs` header comment: every xdg_toplevel becomes an NSWindow, every xdg_popup a borderless child window.
- **Private API**: `compositor/src/mac.m` L1024-1026 `dlsym`s `_LSGetCurrentApplicationASN`, `_LSSetApplicationInformationItem`, `_kLSDisplayNameKey` from LaunchServices (private symbols) to set Dock app names. Not App Store-safe; fine for a self-hosted tool.
- **Guest fetch**: `guest/build-sommelier.sh` downloads ChromiumOS `platform2/vm_tools/sommelier` as `refs/heads/main` tarball (unpinned). The guest package also ships a **prebuilt** `guest/payload/sommelier` binary. `guest/steam/fetch-steam-arm64.py` downloads Valve's Steam client zips from `client-update.steamstatic.com` (SHA-256 verified against the manifest). `kernel/build-kernel.sh` downloads `cdn.kernel.org`.
- **Input/clipboard/HiDPI**: handled by sommelier in the guest and by `comp.rs` / `mac.m` on the host (modifier sync, held-key release on focus change, Retina DPI settings in `guest/x11/Xresources`). Clipboard and popup specifics were not traced.
- **Tests**: `compositor/tests/presentation.m`, `compositor/tests/wayland-stress.py`, `compositor/tests/README.md`. No Rust unit-test suite found. Evidence logs in `evidence/` are the main validation.
- **Code hygiene (compositor/src + top-level .m)**: `unsafe` on 52 lines, `unwrap()/panic!` on 18 lines, TODO/FIXME 0.
- **Commit authorship**: 35 commits. 28 authored as `Claude <noreply@anthropic.com>`, 7 by Jayden (`Quiet-Wolfe`). Tests and evidence are in the repo, and the README records "verified" results (vulkaninfo, compute smoke test) with evidence paths. The README itself states the tearing bug and the Venus context-destroy abort as open defects.

---

## Assumptions

- cloc numbers exclude the vendor/third_party trees. Wawona's `weston-13.0.0` and `waypipe` path dependencies were excluded from LOC.
- `Cargo.lock` package counts are proxies for dependency-graph size. Per-crate licences were **not** verified (no `cargo metadata` or `cargo deny` was run, per instruction). The licences listed for Rust crates are from their manifests and the `deny.toml` allow-list.
- The fork lag (waypipe-darwin on 0.11.2 vs upstream 0.11.3) is inferred from `Cargo.toml` and the tag list; the fork's git history was not diffed commit by commit.
- Wawona's `macOS` NSWindow model and the iOS/macOS renderer paths were only sampled, not traced end-to-end.
- VZCustomVirtioDevice is assumed to be a public macOS 27 API (the repo targets macOS 27, and the entitlement is the standard virtualization one). Not checked against the SDK.

---

## Opinions

- The four projects vary a lot in quality. cocoa-way and vzgpu are internally consistent and have explicit test/evidence discipline. Wawona has the widest scope but the most risk. waypipe-darwin is the smallest and most reusable, but it is a stale patch set.
- The `unwrap()`/`panic` counts across cocoa-way and waypipe-darwin are high for production Rust (1.4k and 0.7k). Most sit in tests or in inherited upstream code, so this is a maintenance concern more than a known crash risk.
- Presence of "App Store-compliant" claims in Wawona next to an in-tree AMFI-bypass/SIP-off code path, plus GPL `waypipe` linked into the same static library, is a reputational and legal risk for any App Store release. Opinion only, not a legal review.
- AI-authored commits (vzgpu) are judged on the code: the protocol and VM glue is coherent, the bug list is honest, and the evidence is real. The main quality gaps are the unpinned sommelier download, no Rust test suite, and the vsock claim in a commit message that the code does not implement.

---

## Verdicts

| Project | Verdict | Reason |
| --- | --- | --- |
| **Upstream waypipe v0.11.3** | **Adopt as dependency (external binary)** | Only candidate with documented `--vsock`, latest tag is v0.11.3, GPL-3.0-or-later (fine for an external process, not for linking). No macOS support upstream, so it must run on the guest only, or be paired with a patched macOS build. Pin the tag and check the `--vsock` path works from the guest side. |
| **waypipe-darwin** | **Vendor-fork (rebase onto v0.11.3), or study only** | The 335-line Darwin delta vs 0.11.2 is small and well scoped (memfd, ppoll, video/dmabuf gating). Lag of one minor version plus 128 TODOs and 773 unwrap/panic hits mean it needs review before use. If the macOS client is needed, rebase the patch onto upstream 0.11.3 instead of depending on this fork directly. GPL. |
| **cocoa-way** | **Study only** | Useful reference for winit-per-toplevel rootless mode, Metal layer rendering, Apple Container `--publish-socket` transport, and clipboard bridge. It is an application (no lib target), GPL-3.0-only, 60k lines of Rust, and does not do vsock. Not a dependency candidate. Consider its Smithay vendoring pattern (`vendor/sources.toml` + patch set) as a model. |
| **vzgpu** | **Study only** (vendor-fork only the Virtualization.framework bits if we need them) | The best reference for a VZ + Venus + cross-domain host stack, and MIT-licensed, so the VMM and cross-domain code could be reused with attribution. But it is an 8.5k-line research prototype with open defects (tearing, Venus destroy abort), uses private LaunchServices symbols, has no vsock (uses vmnet + SSH and Unix sockets), and depends on an unpinned sommelier fetch plus a prebuilt binary. Reuse the design, not the code as-is. |
| **Wawona** | **Reject** | Very broad scope (243k lines across 8+ platforms) with 265 `unsafe` lines. In-tree iland Mode B documents SIP-off, AMFI bypass, and WindowServer code injection. It runtime-fetches a catalog from `repo.wawona.io`. It bundles GPL `waypipe` while its own `deny.toml` disallows GPL. Too much surface to audit for a dependency, and the licensing and security posture conflicts with our goals. |

## Follow-ups (not done here)

- Run `cargo deny check licenses` and `cargo audit` on the cocoa-way and waypipe-darwin locks, and confirm crate licences (not verified in this review).
- Confirm upstream waypipe `--vsock` end-to-end with a vzgpu guest (the guest can talk over the vmnet IP or a Unix socket bridge; vsock is not wired in vzgpu).
- Check whether the vzgpu sommelier source can be pinned to a commit hash.
