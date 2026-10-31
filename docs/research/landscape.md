# Landscape (Phase 0)

Date: 2026-10-31. Synthesis of five research notes in this directory. Every item carries its trust level:
**[P]** primary source seen, **[S]** secondary/community only, **[U]** unknown or unverified. Nothing here has been run on this machine yet; Phase 1 spikes do that.

Sources: [vm-layer](vm-layer.md) · [mac-compositors](mac-compositors.md) · [flathub-flatpak](flathub-flatpak.md) · [integration-areas](integration-areas.md) · [transports-ux-tooling](transports-ux-tooling.md)

Research quality caveat: the notes were written by fast subagents. Apple developer pages returned titles only, and gitlab.freedesktop.org (waypipe) was blocked. Two cited issue trackers (`vergil-project/.github`, `logical-minds-foundry/.github`) are unfamiliar orgs; treat their claims as rumor until reproduced.

## 1. Where the hypotheses stand

| # | Hypothesis | Status | Evidence |
|---|---|---|---|
| H1 | One hidden arm64 Linux VM on Virtualization.framework is viable | Likely | Lima vz default since v1.0 [P]; Lima ran Linux fine on macOS 27.0.1 [S] |
| H2 | Flathub is a usable catalog | Partly | Builds x86_64+aarch64 by default [P]; no published aarch64 app count [U]; terms/rate limits unknown (terms page 404) [U] |
| H3 | Cocoa-Way gives per-toplevel Mac windows | Plausible | README documents Rootless mode, popups, clipboard, input [P]; never run; latency "under investigation" by author [P] |
| H4 | Venus/GPU works in VZ on macOS 27 | Unproven | Only vzgpu (0 stars, 10 days old) and one Medium post [S]; tearing + VMM abort open [P] |
| H5 | Rosetta in Linux VM persists on macOS 27 | Conflicting | Apple doc exists (title) [P-title]; Parallels blog says broader Rosetta support ends in macOS 28 [S]; trackers disagree |
| H6 | WSLg-style RDP RAIL is a good transport | Weak | FreeRDP client RAIL on macOS unverified [U]; WSLg itself uses VAIL (shared memory) which has no macOS equivalent |
| H7 | Mac App Store viable | Doubtful | Sandbox + `com.apple.security.virtualization` workable but unverified [U]; assume direct notarized distribution |

## 2. Comparison matrix

Scores 1 (poor) to 5 (strong). "Custom code" is inverted: 5 means little custom code. Scores are opinion built on the cited facts, not measurements.

### Display / compositor path

| Option | Perf | App compat | Mac integration | Custom code | Maturity | License | Bus factor | macOS 27 fit |
|---|---|---|---|---|---|---|---|---|
| Cocoa-Way (+waypipe-darwin) | 3? | 3? | 4 (native windows, Metal, clipboard, CoreAudio) | 4 | 2 (10 months, ad-hoc signed) | GPL-3.0 (1) | 1 (one dev: 104 of ~111 commits) | 3 (README says macOS 26; 27 untested) |
| Wawona | ? | ? | 2 (single CAMetalLayer path; no per-window evidence) | 2 | 2 | MIT (5) | 1 (one dev: 1258 commits) | 3 |
| Smithay + own macOS backend | ? | ? | 5 (we control it) | 1 (months of work) | 4 (lib), 1 (macOS backend) | MIT (5) | 4 | 3 |
| vzgpu (VM + Venus + vzcomp) | ? | 1 | 3 | 3 | 1 | MIT (5) | 1 | 4 (tested 27.2 on M5) |
| FreeRDP/Weston RAIL | ? | ? | 2 | 2 | ? | Apache-2.0 (5) | 4 | ? |
| XQuartz | 3 | X11 only | 3 | 5 | 4 | no license declared | 2 | 3 |

### VM layer

| Option | Perf | Mac integration | Custom code | Maturity | License | Bus factor | macOS 27 fit |
|---|---|---|---|---|---|---|---|
| Raw Virtualization.framework | 5 | 5 | 2 (we write the VM manager) | 5 | Apple | 5 | 5 (custom virtio, USB, DiskImageKit are 27-only) |
| Lima (vz) | 4 | 3 | 4 | 4 (v2.2.1, 2026-10-03) | Apache-2.0 | 4 | 3 (no 27 notes found; no custom-virtio exposure) |
| Apple container / Containerization | 4 | 4 | 3 | 3 (CLI breaking changes pre-1.0 policy) | Apache-2.0 | 4 | 3 (requires macOS 26; 27 unknown) |
| libkrun / krunkit | 4 (Venus via MoltenVK) | 2 | 3 | 3 (libkrun 2.0 breaks 1.x) | Apache-2.0 | 3 | ? |

Opinion: raw Virtualization.framework behind a thin Swift seam is the only path that exposes macOS 27's custom virtio devices. Lima is the fallback for VM lifecycle. Both need a spike before choosing.

## 3. Key open questions that decide the architecture

1. Does Cocoa-Way Rootless actually run on macOS 27 against a VZ guest over vsock, and what is its input-to-photon latency? (spike 3)
2. Is GPU needed for the apps we care about, or is CPU (llvmpipe) good enough for a first release? (spike 4)
3. What does the Apple Rosetta doc body say, and does it work in a 27 guest? Needs a browser read of the page. (spike 5)
4. What guest page size is required? Rosetta and Venus each reportedly want 4 KiB vs 16 KiB host pages [S]. (spike 1/4)
5. Flathub terms and API stability: need a written answer from Flathub, or mirror the ostree repo and use AppStream data from it instead of the API.

## 4. "What cannot work reliably" register (initial)

| Item | Severity | Basis | Mitigation / UI treatment |
|---|---|---|---|
| Webcam, Bluetooth in guest | High | no known path [U] | Non-goal; show "unsupported" on app detail |
| x86-only Flathub apps | High | aarch64 ~1.3% of downloads [S]; count unknown | Compatibility badge "no ARM build"; optional Rosetta/FEX path later |
| GPU-heavy apps (games, Steam) | High | vzgpu: Steam blocked, tearing [P] | Rating "known broken" until spike 4 passes |
| Single-maintainer compositor (Cocoa-Way / Wawona) | High | contributor counts [P] | Seam around compositor; fallback plan in ADR |
| GPL-3.0 compositor vs licensing | High | license [P] | Decision at Phase 1 gate (belongs to the user) |
| Tearing / frame pacing | Medium | vzgpu open defect [P] | Measure in spike 3; host-side present sync |
| IME, drag-and-drop, native file dialogs | Medium | nothing verified [U] | Spike 5; portal backend only if cheap |
| Rosetta continuity beyond macOS 27 | Medium | conflicting reports | Do not depend on it; FEX fallback |
| macOS 27.0.1 VZ crash on unmapped guest write | Medium | single report [S] | Reproduce; pin guest kernel |
| Flathub API/terms | Medium | terms 404 [U] | Mirror + verify via ostree GPG; ask Flathub |
| Mac App Store distribution | Low priority | unverified | Direct notarized + Sparkle |
| VPN / sleep-wake networking | Medium | not researched | vmnet (available since macOS 26 [P]); test in spike |

## 5. Dependency candidates (preliminary; full vetting in `docs/dependencies.md` after the gate)

| Candidate | Role | License | Last release seen | Note |
|---|---|---|---|---|
| Virtualization.framework | VM | Apple | n/a | first-party |
| Cocoa-Way v2.1.2 | compositor | GPL-3.0 | 2026-10-21 | licensing decision |
| waypipe-darwin v0.11.2-darwin.1 | transport | GPL-3.0 | 2026-10-02 | upstream waypipe license unverified |
| xwayland-satellite | Xwayland rootless | MPL-2.0 | unknown | guest side |
| Sparkle 2.10.1 | updates (EdDSA) | MIT? [U] | 2.10.1, year unseen | verify license |
| swift-argument-parser 1.8.2 | `crosswindctl` | likely Apache-2.0 [U] | 2026-06? | Apple |
| swift-snapshot-testing | visual regression | MIT? [U] | unknown | |
| MCP swift-sdk | control interface | Apache-2.0/MIT | unknown | optional |
| SwiftLint 0.65.1, swift-format 604.0.0 | lint/format | unverified | 2026 | pick one formatter |
| MetricKit vs Sentry | crash reports | Apple / MIT | n/a | default MetricKit, no third-party SDK until justified |

## 6. Phase 1 plan (next)

Spikes, each with a reproducing script under `spikes/` and numbers in `docs/research/spike-N.md`:
1. Boot arm64 Linux on VZ; cold boot, resume, idle RAM, disk (also resolves page size).
2. Flatpak in guest with 5 apps (GTK4, Qt, Electron, X11-only, x86-only). Includes measuring `flatpak remote-ls --arch=aarch64`.
3. Cocoa-Way Rootless + waypipe over vsock vs. fallback; latency, tearing, HiDPI, window behavior.
4. GPU: vzgpu path vs llvmpipe.
5. Integration probes (clipboard, audio, DnD, IME, portals, virtiofs, Rosetta).
6. Packaging: sign, hardened runtime, notarize a minimal VZ app (needs a Developer ID from you; I will prepare everything else).

Prerequisites to check on this machine first: Xcode version, Rust toolchain, `gh`, free disk, chip/RAM. Items needing you later: Developer ID identity and notarization credentials (spike 6), plus the licensing and name decisions at the gate.

Not yet researched (carry into Phase 1): audio path, portals backend, StatusNotifier, free page reporting, qemu-user, App Review rules, HIG pages for macOS 27 (read in a browser), UTM, upstream waypipe.
