# AGENTS.md

Crosswind runs Linux GUI apps as native Mac windows. Public beta; nothing earlier is in use, so keep no legacy or migration code. Read `docs/ROADMAP.md` and `docs/adr/` before changing architecture, and do not reopen decided choices.

## Gotchas

- Three processes: store app `Crosswind` (`App/Store`), background agent `CrosswindHost` (`App/Host`, the only one with the virtualization entitlement), and per-app stub `CrosswindAppStub` (`App/Stub`). Guest daemon `crosswindd` is Rust in `guest/`, talking to the host over vsock (ports 5000 display, 5001 control); schemas in `proto/`, generated Swift in `Packages/CrosswindKit/.../Generated` (`make proto`).
- `guest/` is built inside the Lima VM `cwbuild` (Alpine), never on the Mac. Start it with `limactl start cwbuild`.
- `Crosswind.xcodeproj` is generated from `project.yml` and gitignored; run `make project` after changing the spec.
- `spikes/` is throwaway research. Do not change it.
- `make image` can fail with apk `DNS: transient error`; the fix is in `docs/KNOWLEDGE.md` ("Lima DNS").
- `crosswindctl exec` and the guest daemon log (`/run/crosswind/crosswindd.log`) work only against a debug agent (`CROSSWIND_DEBUG=1`, set by `make dev-agent` and `scripts/ctl.sh --rebuild`). To use them with a production build: `launchctl setenv CROSSWIND_DEBUG 1`, restart the agent, then `launchctl unsetenv CROSSWIND_DEBUG`.
- The website in `site/` (Astro) syncs its docs from `docs/` at build time and deploys with `npm run deploy` (wrangler) to crosswind.nandan.fyi.

## Commands

- `make project`, `make build`, `make test` (app tests), `cd Packages/CrosswindKit && swift test`, `make lint` (SwiftLint and `swift-format lint`, check only), `make format`, `make proto`.
- `make guest` (release `crosswindd` in the Lima VM), `make image` (`DEBUG_TOOLS=1` adds strace and friends), `make dev-image` (install it for the dev agent), `make dev-agent` (register the Debug agent).
- `sh scripts/ctl.sh <args>` runs `crosswindctl` from a project-local build; `--rebuild` rebuilds and re-registers the agent. `docs/DEVELOPMENT.md` has setup and debugging.
- Guest checks, inside the VM: `cargo clippy --locked --all-targets -- -D warnings` and `cargo test --locked`.
- `make release` builds, signs, notarizes (via `asc`) and packages the DMG. Follow `docs/release.md` and `docs/beta-checklist.md`; only release when the owner asks.

## Conventions

- Swift 6 language mode, macOS 27 target, four-space indentation, lines up to 120 columns.
- Use Xcode's `xcrun swift-format` and SwiftLint with the root `.swift-format` and `.swiftlint.yml`. Do not add SwiftFormat.
- Every Swift source file starts with `SPDX-License-Identifier: AGPL-3.0-or-later`.
- Signing is ad-hoc by default; release builds use Developer ID (team `72CW7UW6RB`). The apps are not sandboxed.
- No dead code, no speculative abstractions, no second way to do one thing, no legacy paths. Where macOS already offers a setting (default apps), do not rebuild it.
- Test what you change. Guest-hostile input is validated on both sides (`DisplayLimits`, `limits.rs`).
- Commit and push to `main` after each significant change.
- For GUI behavior you cannot verify automatically (sharpness, typing feel, IME, drag and drop, audio), tell the owner exactly what to test; `docs/beta-checklist.md` has the list.

## Status

Beta 2 is published. Open work is in GitHub issues; `docs/ROADMAP.md` summarizes it and `docs/KNOWLEDGE.md` has session notes. Read them before picking up work.
