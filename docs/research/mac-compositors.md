# Showing Linux Wayland/X11 toplevels as native macOS windows: existing options

Research date: 2026-10-31. Target: macOS 27, Apple silicon. Goal: one Mac window per Linux toplevel.

Method: GitHub REST API via `gh` (metadata, releases, commits, contributors, issues), README reads, and WebSearch for projects not on GitHub. Metrics are a snapshot taken on 2026-10-31. "Unknown" means not verified in this pass.

---

## Facts

Each fact cites its source. Access date for every item: 2026-10-31.

### Cocoa-Way (J-x-Z/cocoa-way)

- License GPL-3.0. Stars 1069. Created 2025-12-13. Last push 2026-10-21. Latest release v2.1.2, published 2026-10-21. Open issues 0. Language Rust. Source: https://api.github.com/repos/J-x-Z/cocoa-way (metadata); https://api.github.com/repos/J-x-Z/cocoa-way/releases/latest
- Contributors: J-x-Z 104 commits, Cass67 3, KirisameLonnet 2, web-flow 1, GT-610 1 (the API lists 5 at most; 7 total). Source: https://api.github.com/repos/J-x-Z/cocoa-way/contributors
- Has a **Rootless** presentation: "maps each xdg-toplevel to a native macOS window, forwarding move, resize, minimize, maximize, fullscreen, titles, popups, and per-surface input." Also a **Desktop** mode that maps Linux windows into one compositor window. Source: https://github.com/J-x-Z/cocoa-way (README, "Presentation modes")
- Clipboard: "Bidirectional text and PNG clipboard (images up to 64 MiB)". Keyboard, pointer, gestures. CoreAudio forwarding. Native Metal renderer with "Retina scaling and damage-aware SHM uploads". Source: README "Highlights" table.
- Transport: Waypipe over SSH, Apple Container, Docker/OrbStack, or a local Waypipe socket. Requires `waypipe-darwin` on the Mac. Source: README "What is Cocoa-Way?" and "Build from source".
- Release artifacts are ad-hoc signed, not Apple-notarized. Source: README "Release archive".
- README states: "End-to-end input and display latency remains under investigation; this update does not claim to eliminate it." Source: README, v2.1.1 paragraph.
- Apple Container requirement: "officially supports it on Apple silicon with macOS 26". No README statement covers macOS 27. Source: README "Apple Container" section.
- Desktop Background is "experimental" and "does not extend into other apps' fullscreen Spaces or the macOS lock screen." Source: README "Desktop Background (experimental)".
- Recent issues (all closed): #30 "Touchpad inertia is applied twice" (closed 2026-10-10); #26 homebrew install step missing; #24 "waypipe: command not found"; #22 "Crashes with Namespace SIGNAL, Code 6, Abort trap: 6" (2026-07-18); #15 "Crashes on system without third-party dependencies installed via homebrew"; #9 "CPU占用太高" (high CPU); #8 "Offset when opening programs". Source: `gh issue list -R J-x-Z/cocoa-way --state all`
- Cocoa-Way is also the compositor used by the vzgpu project (its README says "Cocoa-Way 2.0.3"). Source: https://github.com/Quiet-Wolfe/vzgpu (README, "Status")

### Wawona (Wawona/Wawona)

- License MIT. Stars 282. Last push 2026-10-27. Latest release v26.8.12, published 2026-08-12. Open issues 111. Language Rust. Source: https://api.github.com/repos/Wawona/Wawona ; https://api.github.com/repos/Wawona/Wawona/releases
- Contributors: aspauldingcode 1258 commits; next largest 9 (insomnia-creator). Source: https://api.github.com/repos/Wawona/Wawona/contributors
- Self-description: "a native Wayland compositor for macOS, iOS, iPadOS, tvOS, watchOS, visionOS, Android, and Linux." Source: https://github.com/Wawona/Wawona (README)
- Per-platform table: macOS present path is "Mode A: CAMetalLayer / `WWNIlandPresenter`", "Mode A default (store-safe)". Mode B is "SIP-gated Desktop Replacement". Source: https://github.com/Wawona/Wawona/blob/development/docs/2026-SOURCE-OF-TRUTH.md (fetched via API contents)
- X11: "Wawona has no local X server on any platform." X11 is served via remote XWayland over waypipe, or nested Weston XWayland on non-store macOS builds. Source: same file, "X11 story".
- Graphics default: KosmicKrisp on Apple silicon with macOS 26+, else MoltenVK. Source: same file, "Settings inventory".
- Open issues are mostly TestFlight crash reports on iOS (e.g. #207 to #222, filed 2026-10-24 to 2026-10-28), plus #217 (Android SSH failing), #218 (Android foldable layout), and #223 (auto-relaunch after quit, platform not stated). Source: `gh issue list -R Wawona/Wawona --state open`
- Mentions of macOS windowing: the README only says "Wayland apps and desktops draw into a native window on the device." It does not say each toplevel becomes its own NSWindow. Source: https://github.com/Wawona/Wawona (README, "What can you do with Wawona?")
- Also contains a Smithay adoption decision doc (RFC #35 closure). Its content was not read in this pass. Source: https://github.com/Wawona/Wawona/blob/development/docs/2026-SOURCE-OF-TRUTH.md (link list)

### vzgpu (Quiet-Wolfe/vzgpu)

- License MIT. Stars 0. Created 2026-10-15. Last push 2026-10-15. Latest tag kernel-7.2.11-vzgpu, published 2026-10-15. Open issues 0. Language Objective-C. Source: https://api.github.com/repos/Quiet-Wolfe/vzgpu ; /releases/latest
- Contributors: claude 28 commits, Quiet-Wolfe 7 commits. Source: https://api.github.com/repos/Quiet-Wolfe/vzgpu/contributors
- Architecture: a Virtualization.framework VM with a Venus virtio-gpu, a cross-domain Wayland passthrough, and a macOS compositor (`vzcomp`). It is not a host compositor for Linux apps. Guest apps run in a Linux VM. Source: https://github.com/Quiet-Wolfe/vzgpu (README, first paragraph)
- Status as of 2026-10-15: Venus gate PASS on macOS 27.2 with M5 (guest `vulkaninfo` shows Venus). Guest vkcube opens a native macOS window "at ~55 commits/s". Source: README "Status".
- Open defects listed by the author: "Tearing / stale frames" (early `wl_buffer.release` by the compositor), and a "VMM abort on Venus context destroy" (virglrenderer race, with a local patch). Source: README "Open defects" and "virglrenderer fence bugs".
- Run path requires a specific local virglrenderer build, Fedora 45 Beta guest, sommelier built from ChromiumOS, and `tools/run-vm`. Source: README "Running".
- Known gap: `Wayland passthrough: window appears, but tears (not done).` Source: README "Status".

### waypipe-darwin (J-x-Z/waypipe-darwin) and upstream Waypipe

- waypipe-darwin: GPL-3.0. Stars 47. Last push 2026-10-02. Latest release v0.11.2-darwin.1 published 2026-10-02. Open issues 1. Description: "Specialized fork of Waypipe optimized for macOS (Darwin). Features patched Shared Memory (SHM) and socket handling." Source: https://api.github.com/repos/J-x-Z/waypipe-darwin ; /releases/latest
- Contributors: mstoeckl 783 (upstream author), J-x-Z 20, jbeich 10, and others. Source: https://api.github.com/repos/J-x-Z/waypipe-darwin/contributors
- The fork's README says it "stays close to upstream 0.11" and needs OpenSSH for socket forwarding. Source: WebSearch result snippet, https://github.com/J-x-Z/waypipe-darwin (not fully fetched).
- Upstream Waypipe (gitlab.freedesktop.org/mstoeckl/waypipe): WebFetch was blocked by an Anubis bot challenge; no license, release, or macOS statement could be read. Status: unknown. Source: https://gitlab.freedesktop.org/mstoeckl/waypipe (blocked)
- No official macOS port was found in search. Source: https://www.mankier.com/1/waypipe and related man pages (Linux-only usage shown).

### Smithay (Smithay/smithay)

- License MIT. Stars 3357. Last push 2026-10-29. Latest release v0.7.0, published 2025-06-24 (tag is over a year old). Open issues 288. Language Rust. Source: https://api.github.com/repos/Smithay/smithay ; /releases/latest
- Contributors: Drakulix 1900, cmeissl 514, elinorbgr 342. Source: https://api.github.com/repos/Smithay/smithay/contributors
- Smithay is a library ("A smithy for rusty wayland compositors"), not an end-user app. Source: same API metadata.
- macOS support: unknown. Not checked in this pass.

### XQuartz (XQuartz/XQuartz)

- License: none declared in GitHub API metadata (`license: null`). Stars 1071. Last push 2026-08-18. Latest release XQuartz-2.8.6, published 2026-07-14. Open issues 39. Source: https://api.github.com/repos/XQuartz/XQuartz ; /releases/latest
- 2.8.6 notes: CVE fixes in components, arm64 glxinfo/glxgears, an Apple Silicon display bug fix, a 2.8.5 rendering regression fix, and an xrandr crash fix. Install requires macOS 10.13 or later. Rootless mode is not mentioned in the release notes. Source: https://www.xquartz.org/releases/XQuartz-2.8.6.html (WebSearch snippet)
- Rootless: Wikipedia describes X windows showing up on the Quartz desktop. Source: https://en.wikipedia.org/wiki/XQuartz (WebSearch snippet)
- Open discussion: window redraw on resize on Tahoe; a commenter said Tahoe 26.5 fixed it. Source: https://github.com/orgs/XQuartz/discussions/478 (WebSearch snippet)
- XQuartz is an X11 server, not a Wayland compositor. It needs X clients, so it does not directly host Wayland toplevels. Source: https://github.com/XQuartz/XQuartz (repo description)

### FreeRDP and Weston RDP/RAIL

- FreeRDP: Apache-2.0. Stars 13918. Last push 2026-10-31. Latest release 3.32.2, published 2026-10-12. Open issues 217. Source: https://api.github.com/repos/FreeRDP/FreeRDP ; /releases/latest
- Weston's RDP backend uses FreeRDP as its RDP server. RAIL/VAIL support for remoting individual windows came from Microsoft's WSLg work. Source: https://manpages.ubuntu.com/manpages/questing/man7/weston-rdp.7.html and https://github.com/microsoft/wslg/blob/main/README.md (WebSearch snippets)
- The WSLg README says only VAIL support is effectively used in WSLg. Source: https://github.com/microsoft/wslg/blob/main/README.md (WebSearch snippet)
- Whether the FreeRDP client supports RAIL on macOS: unknown. One blog post said RAIL in the FreeRDP client "would be cool," which suggests it lacked RAIL at that time. Source: https://blog.jacobstoner.com/wayweston-rdp/ (WebSearch snippet, date unknown)

### Discovery searches

- `gh search repos "macOS wayland compositor"` returned Wawona (282 stars) and a 0-star automated report on Cocoa-Way. Source: GitHub search via `gh`.
- `gh search repos waypipe` returned J-x-Z/waypipe-darwin (47 stars) and cocoa-way. Source: GitHub search via `gh`.
- Searches for "WSLg for Mac" and "Weston RDP RAIL FreeRDP macOS" returned no projects. Source: GitHub search via `gh`.

---

## Assumptions

- A1: The user wants per-toplevel NSWindows and can accept a GPU-accelerated path only if it is actually verified. Software SHM is acceptable as a baseline.
- A2: Distributing GPL-3.0 code inside a closed-source or App Store product is not acceptable. This is a common constraint but needs confirmation from the user.
- A3: Star counts and issue counts are a snapshot as of 2026-10-31 and will drift.
- A4: "macOS 27 status" is judged only from README claims and dated test notes. No project was run in this pass.

---

## Opinions

- O1: Cocoa-Way is the closest existing fit. It already implements per-toplevel native windows (Rootless), popups, clipboard, and keyboard/pointer input, and it is actively released. Its weaknesses are the GPL-3.0 license, a young project (created 2025-12-13, about 10 months old at the check date), a single-maintainer history (J-x-Z holds most commits), and the author's own statement that latency is still under investigation.
- O2: Wawona has more surface area (many platforms) and more open issues. Its macOS path is documented as a single CAMetalLayer present path, and nothing found shows per-toplevel windows. For this goal it looks like a platform-spread project that is not focused on the mapping feature.
- O3: vzgpu is research-grade. It is 0 days of public history, has 0 stars, and its README lists open tearing and crash defects. It is useful as evidence that a Venus GPU path on macOS 27 is possible, but it is not a usable option today.
- O4: waypipe-darwin is a necessary piece for any remote-Wayland path on macOS (SHM and socket handling). It is not a compositor.
- O5: Smithay is the most permissive base (MIT) with the largest contributor base, but it is a library. Building a macOS backend on it means real custom work (EGL/Metal bridge, input, AppKit window mapping). Its release tag is stale (2025-06-24) even though the repo is active.
- O6: XQuartz is not a Wayland option. It serves X11 clients only, so it does not solve the Wayland side. It is only relevant if X11 apps must be supported.
- O7: FreeRDP/Weston RAIL is a plausible route for windows-level remoting, but RAIL client support on macOS is unverified. Treat as a research spike, not a ready option.

---

## Comparison table

Values come from the Facts above. "Unknown" = not verified.

| Project | License | Stars | Last push | Latest release | Open issues | Contributors (top) | Per-toplevel native window on macOS | Popups | HiDPI | Input | Clipboard | DnD | GPU path | Apple silicon / macOS 27 | Code size | Custom work needed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Cocoa-Way | GPL-3.0 | 1069 | 2026-10-21 | v2.1.2 (2026-10-21) | 0 | J-x-Z (104) | Yes (Rootless) | Yes (README) | Yes (Retina) | Keyboard, pointer, gestures | Text + PNG | Unknown | Metal renderer; SHM upload | Apple silicon; macOS 26 stated for Apple Container; macOS 27: unknown | Unknown | Unknown; Waypipe required; GPL concern |
| Wawona | MIT | 282 | 2026-10-27 | v26.8.12 (2026-08-12) | 111 | aspauldingcode (1258) | Unknown (single CAMetalLayer path documented) | Unknown | Unknown | Unknown | Unknown | Unknown | KosmicKrisp / MoltenVK | macOS 26+ stated; macOS 27: unknown | Unknown | Verify per-toplevel mapping; cross-platform scope |
| vzgpu | MIT | 0 | 2026-10-15 | kernel-7.2.11-vzgpu (2026-10-15) | 0 | claude (28), Quiet-Wolfe (7) | Yes, via Cocoa-Way (window appears; tears) | Unknown | Unknown | Unknown | Unknown | Unknown | Venus over virtio-gpu (passed compute smoke test) | macOS 27.2 and M5 tested | Unknown | Full VM stack; fix tearing; virglrenderer patch |
| waypipe-darwin | GPL-3.0 | 47 | 2026-10-02 | v0.11.2-darwin.1 (2026-10-02) | 1 | mstoeckl (783), J-x-Z (20) | N/A (transport) | N/A | N/A | N/A | N/A | N/A | N/A | Unknown | Unknown | Needed as transport; license |
| Waypipe upstream | Unknown | Unknown | Unknown | Unknown | Unknown | Unknown | N/A | N/A | N/A | N/A | N/A | N/A | N/A | Not documented for macOS | Unknown | Unknown |
| Smithay | MIT | 3357 | 2026-10-29 | v0.7.0 (2025-06-24) | 288 | Drakulix (1900) | Library only | Library | Library | Library | Library | Library | Library | Unknown | Unknown | Full macOS backend |
| XQuartz | None declared | 1071 | 2026-08-18 | XQuartz-2.8.6 (2026-07-14) | 39 | Unknown | X11 only; rootless windows (Wikipedia) | Unknown | Unknown | Unknown | Unknown | Unknown | Unknown | Apple silicon: fixes in 2.8.6 | Unknown | Not Wayland; no license |
| FreeRDP (+ Weston RAIL) | Apache-2.0 | 13918 | 2026-10-31 | 3.32.2 (2026-10-12) | 217 | Unknown | Unknown (RAIL on macOS client unverified) | Unknown | Unknown | Unknown | Unknown | Unknown | Unknown | Unknown | Unknown | Verify RAIL client; custom server |

---

## Real reported problems (from READMEs and issues)

- Cocoa-Way: touchpad inertia applied twice (#30, closed); crash on SIGNAL 6 (#22, closed); crash without Homebrew dependencies (#15, closed); "waypipe: command not found" (#24, closed); high CPU (#9, closed); offset when opening programs (#8, closed). All open issues are closed. Source: `gh issue list -R J-x-Z/cocoa-way --state all`
- Wawona: 111 open issues, most are TestFlight crash reports on iOS, plus Android and an auto-relaunch report (#223). No open issue found about per-window mapping on macOS. Source: `gh issue list -R Wawona/Wawona --state open`
- vzgpu: open defects in README: tearing and stale frames; VMM abort on Venus context destroy (virglrenderer race). Source: https://github.com/Quiet-Wolfe/vzgpu
- XQuartz: open discussion on window redraw on resize on Tahoe. Source: https://github.com/orgs/XQuartz/discussions/478

---

## Recommendation (opinion)

1. Study Cocoa-Way's Rootless path first. It already proves the per-toplevel window model on macOS. License (GPL-3.0) decides whether it can be reused or only referenced.
2. If a permissive base is needed, Smithay (MIT) plus a custom macOS backend is the path. Expect months of work; do not promise GPU support without a spike.
3. Keep vzgpu as a GPU research track, not a shipping option.
4. Run a spike on FreeRDP/Weston RAIL only if an RDP-based design is acceptable.

---

## Search log

- `gh api repos/<owner>/<repo>` for J-x-Z/cocoa-way, Wawona/Wawona, Quiet-Wolfe/vzgpu, Smithay/smithay, FreeRDP/FreeRDP, XQuartz/XQuartz, J-x-Z/waypipe-darwin: metadata, releases, commits, contributors, README, issues.
- `gh api repos/linux-wayland/waypipe`, `repos/mstoeckl/waypipe`, `repos/talex5/waypipe`, `repos/waypipe-darwin`: 404 (not on GitHub under those names).
- `gh search repos "macOS wayland compositor"`, `"WSLg for Mac Linux apps native macOS windows"` (empty), `"Weston RDP RAIL FreeRDP macOS"` (empty), `"waypipe"`, `"rootless macos x11 xquartz"` (empty).
- WebFetch https://gitlab.freedesktop.org/mstoeckl/waypipe: blocked by Anubis challenge.
- WebSearch: "waypipe macOS darwin port Wayland forwarding"; "XQuartz 2.8.6 release notes rootless"; "FreeRDP RAIL Weston RDP-backend seamless windows macOS client".
- Not done: did not run any project on macOS 27. Did not read Wawona's SOURCE-OF-TRUTH linked docs beyond the top file. Did not check Smithay macOS support. Did not verify upstream Waypipe license or release.
