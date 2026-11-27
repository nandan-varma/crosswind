# CLAUDE.md

Guidance for agents working in this repository. Read it before changing code.

## What this is

Crosswind is a macOS app (AGPL-3.0-or-later, Developer ID distribution) that runs Linux GUI apps as native Mac windows. Apps come from Flathub. Public beta (0.1.0) is the first release; nothing earlier is in use, so there is no legacy or migration code to keep.

## Architecture

- **Three processes.** (1) `Crosswind`, the store app (`App/Store`, SwiftUI). (2) `CrosswindHost`, the background agent (`App/Host`, AppKit accessory app, `LSUIElement`, entitlement `com.apple.security.virtualization`), embedded at `Contents/Library/Helpers` and started on demand by launchd through Mach service `dev.crosswind.host`. The store registers it with `SMAppService.agent` (`App/Store/Resources/dev.crosswind.host.plist`). (3) `CrosswindAppStub` (`App/Stub`, bundle `dev.crosswind.appstub`), a template embedded at `Contents/Resources`; each installed app gets a copy in `~/Applications/Crosswind` with its own icon, name and `CrosswindAppID`.
- **VM (host agent, Virtualization.framework).** Boots an Alpine arm64 guest: uncompressed `Image` kernel, `initramfs`, a read-only `system.erofs` system disk and a data disk. Code: `Packages/CrosswindKit/Sources/CrosswindKit/VM/`. The agent (`Agent/`) owns the VM session, routes windows to stubs, forwards guest control requests, runs a heartbeat watchdog and shows tray icons.
- **Guest daemon `crosswindd` (Rust, `guest/`).** Smithay Wayland compositor with a pixman renderer, a Flatpak/portal/tray/clipboard layer, and xwayland-satellite for X11. It streams per-window damage to the host, LZ4-compressed protobuf over vsock port 5000 (display) and 5001 (control). Schemas: `proto/`.
- **Display (host, AppKit).** Each guest window is a native `NSWindow` (`Display/`). Input, text input, title bar tint and activation requests flow back to the guest.
- **Catalog and store.** Flathub AppStream catalog, popularity from the Flathub API, store UI and onboarding in `App/Store`.
- **Website.** `site/` (Astro), published to https://crosswind.nandan.fyi. Docs there are synced from `docs/` at build time.

## Layout

- `App/Store`, `App/Host`, `App/Stub`: the three apps. `tools/crosswindctl/`: command-line tool (`exec` works only against a debug agent).
- `Packages/CrosswindKit/`: SwiftPM library (Agent, Control, Display, VM, Catalog, Store, Stub, Support) and its tests. Generated protobuf lives in `Generated/` (`make proto`).
- `Tests/CrosswindTests/`: store-app unit tests, hosted by the app.
- `guest/`: Rust workspace, built inside the Lima VM `cwbuild` (Alpine). Not built on the Mac. `image/`: guest image build (`image/build.sh`) and its overlay. `proto/`: protobuf schemas.
- `design/`: generator for the app icon and menu bar glyph. `site/`: website. `scripts/`: dev loop, release and appcast scripts. `docs/`: guides, ADRs, research, compatibility results.
- `spikes/`: throwaway experiments from early research. Do not change them.
- `project.yml`: XcodeGen spec. `Crosswind.xcodeproj` is generated and gitignored.

## Commands

- `make project` (generate the Xcode project), `make build`, `make test` (app tests), `cd Packages/CrosswindKit && swift test`, `make lint` (SwiftLint and `swift-format lint`, check only), `make format`, `make proto`.
- `make guest` (release build of `crosswindd` in the Lima VM), `make image` (guest image; `DEBUG_TOOLS=1` adds strace and friends), `make dev-image` (install it for the dev agent), `make dev-agent` (register the Debug agent with debug mode on).
- `sh scripts/ctl.sh <args>` runs `crosswindctl` from a project-local build; `--rebuild` rebuilds and re-registers the agent. `docs/DEVELOPMENT.md` has the setup and the debugging techniques.
- `make release` builds, signs, notarizes (via `asc`) and packages the DMG; `docs/release.md` and `docs/beta-checklist.md` cover publishing and the manual checks.
- Guest checks, inside the VM: `cargo clippy --locked --all-targets -- -D warnings` and `cargo test --locked`.

## Conventions

- Swift 6 language mode. macOS 27 deployment target. Four-space indentation, lines up to 120 columns.
- `swift-format` (from the Xcode toolchain, `xcrun swift-format`) and SwiftLint with the root `.swift-format` and `.swiftlint.yml`. Do not add SwiftFormat.
- Every Swift source file carries `SPDX-License-Identifier: AGPL-3.0-or-later` in its first line.
- Entitlements: `com.apple.security.virtualization` and `com.apple.security.device.audio-input` (microphone), on `CrosswindHost`. The apps are not sandboxed (direct distribution).
- Signing: ad-hoc (`-`) by default. Release builds sign with Developer ID (team `72CW7UW6RB`).
- No dead code, no speculative abstractions, no second way to do one thing, no legacy paths. Where macOS already offers a setting (default apps), do not rebuild it.
- Test what you change; guest-hostile input is validated on both sides (`DisplayLimits`, `limits.rs`).
- Commits and PRs carry no AI attribution lines. Commit and push after each significant change.

## Status

Public beta readiness. Built and verified on a live guest: installs, windows, input, clipboard, dark mode, notifications, links, file dialogs, shared folders, audio output, tray icons, Open With and URL handlers, onboarding, release pipeline. Open work is in GitHub issues; `docs/ROADMAP.md` summarizes it.
