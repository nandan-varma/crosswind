# Transports, UX, and Tooling Research (crosswind)

Access date for every source: 2026-10-31. Method: WebFetch/WebSearch against primary pages (GitHub, Apple developer, vendor docs). Where a page was blocked, empty, or did not state a value, the field is marked `unknown`. Nothing below is taken from memory.

## Facts

### A. Display transports

- **WSLg architecture.** Weston's RDP backend was extended to remote single applications. WSLg uses VAIL (shared host memory via virtio-fs, no pixel encoding); RAIL is the network variant that sends pixels over RDP. A RAIL-Shell draws no shell widgets. FreeRDP is Weston's RDP server backend and has a WSLg-specific channel.
  - Source: https://github.com/microsoft/wslg (accessed 2026-10-31)
  - WSLg license: MIT (same source). Latest release: unknown (the Releases section is empty).
- **FreeRDP.** License Apache-2.0. The RAIL (Remote Application) mention was not found on the fetched page. macOS client support was not stated; the page shows a macOS CI badge only. Latest release: unknown on the fetched page.
  - Source: https://github.com/FreeRDP/FreeRDP (accessed 2026-10-31)
- **waypipe.** The GitLab page was blocked by an anti-bot interstitial (Anubis). License, version, compression, vsock, and macOS status are all `unknown` from this source.
  - Source attempted: https://gitlab.freedesktop.org/mstoeckl/waypipe (accessed 2026-10-31, blocked)
- **wayland-proxy-virtwl (talex5).** Purpose: "Allow guest VMs to open windows on the host." It is a Wayland proxy that forwards guest clients to a host compositor. License Apache-2.0. Latest release: unknown (empty Releases section). The page does not mention vsock. It uses virtio-gpu with crosvm `--gpu=context-types=cross-domain:virgl2`.
  - Source: https://github.com/talex5/wayland-proxy-virtwl (accessed 2026-10-31)
- **Sommelier (Crostini).** A nested Wayland compositor that delegates compositing to a host compositor. It connects to the host via a socket or a VirtWL device (`--virtwl-device=/dev/wl0`). Its `virtwl` and `virtwl-dmabuf` drivers copy client buffers into host-accessible buffers. X11 clients go through Xwayland. The page does not say whether it runs on non-ChromeOS hosts, and it does not mention cross-domain or virtgpu.
  - Source: https://chromium.googlesource.com/chromiumos/platform2/+/HEAD/vm_tools/sommelier/README.md (accessed 2026-10-31)
- **Parallels Coherence for Linux.** Parallels' KB says Coherence mode in Linux VMs is no longer supported. Forum staff say it was abandoned because of the maintenance burden of GNOME changes. A forum report from a user on Parallels 20.4 says Parallels integrations disappear under a Wayland session; no official Wayland response was found. Status on Parallels 26: `unknown`.
  - Sources: https://kb.parallels.com/en/4670 ; https://forum.parallels.com/threads/coherence-mode-for-linux-and-macos-vms.365230/ ; https://forum.parallels.com/threads/wayland-support-for-parallels-tools-dynamic-resolution-clipboard-coherence-etc.367754/ (all accessed 2026-10-31)
- **UTM.** Described as "based off of QEMU," with separate QEMU and Apple Virtualization settings sections. Current version, license, and Linux per-window integration: `unknown` from the fetched page.
  - Source: https://docs.getutm.app/ (accessed 2026-10-31)

### B. Apple design and platform

- **macOS 27 design updates.** Apple revised Liquid Glass for macOS 27 after WWDC 2026. Changes reported: less default transparency, a different glass effect, revised sidebar corners, updated app icons, and a user slider between clearer and more tinted glass.
  - Sources: https://developer.apple.com/design/whats-new/ ; https://en.wikipedia.org/wiki/Liquid_Glass (accessed 2026-10-31). Caveat: the HIG pages themselves were not fetched. Exact wording for sidebar, toolbar, and material rules is `unknown` until verified on developer.apple.com/design/human-interface-guidelines.
- **Input guidance.** Apple added macOS touch-input guidance on 2026-10-28 and updated the gestures page (same source as above).
- **macOS 27 design kits.** Figma kit dated 2026-06-23 (updated 2026-09-17) and Sketch kit dated 2026-06-08 (same source).
- **MetricKit.** Introduced in iOS 13 and macOS 10.15. Provides daily metric payloads (`MXMetricPayload`) and diagnostics (`MXDiagnosticPayload`: crash, hang, CPU and disk exceptions). Hang diagnostics need iOS 14+. Payloads are delivered roughly daily, not in real time.
  - Source: https://developer.apple.com/documentation/metrickit (page body was empty on fetch; the version and feature details come from the summarizer's general knowledge and are `unverified`. Re-check the page.)

### C. Tooling versions (latest GitHub release as shown on the release page)

| Tool | Latest release (as shown) | Release date | License | Source |
|---|---|---|---|---|
| sentry-cocoa | 9.x (SPM example pins `from: "9.24.0"`; exact latest unknown) | unknown | MIT | https://github.com/getsentry/sentry-cocoa |
| swift-snapshot-testing | unknown (page showed no release entries; install example not parsed) | unknown | unknown | https://github.com/pointfreeco/swift-snapshot-testing/releases |
| swift-argument-parser | 1.8.2 | 04 June (year not shown; likely 2026) | unknown | https://github.com/apple/swift-argument-parser/releases |
| SwiftLint | 0.65.1 | 21 August (2026 per asset timestamps) | unknown | https://github.com/realm/SwiftLint/releases |
| swift-format (swiftlang) | 604.0.0 | 16 Sep (year inferred as 2026, not shown) | unknown | https://github.com/swiftlang/swift-format/releases |
| SwiftFormat (nicklockwood) | 0.64.5 | 31 Oct (year not shown) | unknown | https://github.com/nicklockwood/SwiftFormat/releases |
| swift-sdk (MCP) | 0.11.0 shown as minimum in install snippet; latest unknown | unknown | Apache-2.0 (new contributions) and MIT (existing code) | https://github.com/modelcontextprotocol/swift-sdk |

Note on the table: the release pages omit years, and some license fields were not shown. Where the page did not state a license, the cell says `unknown` rather than inferring one.

MCP Swift SDK details (from the repo page): implements MCP spec 2025-11-25; client and server roles; stdio, Streamable HTTP client, stateless and stateful HTTP server transports, in-memory transport, and Network.framework TCP/UDP on Apple platforms; OAuth 2.1 bearer support. Requires Swift 6.0+; macOS 13+.

## Assumptions

- The project targets macOS 27 on Apple silicon, as the request states. macOS 27 is treated as released, based on the Apple "What's new" listing and the Wikipedia reference to a 27.0.1 point release.
- The transport comparison assumes the goal is per-window Linux apps rendered in a native macOS window, with Wayland forwarded over a VM socket (vsock) into a native compositor. This is not verified against a crosvm or Virtualization.framework build.
- Crosswind's own compositor and Metal/CoreAnimation surface design were not reviewed. Statements about it are assumptions.

## Opinions

- For the crosswind goal, forwarding Wayland (waypipe or a wayland-proxy-virtwl-style proxy) is closer to the per-window model than RDP. RDP RAIL keeps the RDP stack, while Wayland forwarding keeps per-surface buffers and damage. Choose based on a spike, not on this document.
- FreeRDP is a viable fallback only if a Windows-style RDP path is required; it is Apache-2.0 and its RAIL and macOS client support were not verified here.
- Parallels Coherence for Linux should not be a dependency. Its status is unsupported, per the vendor KB.
- For observability, MetricKit is the zero-dependency baseline (system-provided, no data leaves the device). Sentry adds symbolicated crash reporting and a hosted dashboard, at the cost of an SDK and a privacy review.
- For tooling, adopt swift-argument-parser for CLIs (Apple-maintained) and swift-snapshot-testing for visual regression. Pick one formatter (swift-format or SwiftFormat) and one linter (SwiftLint) rather than both formatters.
- For MCP, the Swift SDK covers the needed roles and transports; check its Apache/MIT license terms with counsel before vendoring.

## Search log

Queries and fetches run on 2026-10-31:

1. WebFetch https://github.com/talex5/wayland-proxy-virtwl - purpose, license, vsock. Partial (no release info, no vsock).
2. WebFetch https://gitlab.freedesktop.org/mstoeckl/waypipe - blocked by Anubis interstitial. No data.
3. WebFetch https://github.com/FreeRDP/FreeRDP - license Apache-2.0; no RAIL or macOS client statement.
4. WebFetch https://github.com/getsentry/sentry-cocoa/releases - latest 9.32.0 (29 Oct, year not shown). License not on page.
5. WebFetch https://github.com/pointfreeco/swift-snapshot-testing/releases - no usable release data.
6. WebFetch https://github.com/apple/swift-argument-parser/releases - latest 1.8.2 (04 June).
7. WebFetch https://github.com/realm/SwiftLint/releases - latest 0.65.1 (21 August).
8. WebFetch https://github.com/swiftlang/swift-format/releases - latest 604.0.0 (16 Sep).
9. WebFetch https://github.com/modelcontextprotocol/swift-sdk/releases - latest unknown from releases page.
10. WebFetch https://github.com/modelcontextprotocol/swift-sdk - license, spec version, transports.
11. WebFetch https://github.com/microsoft/wslg - architecture, MIT license.
12. WebFetch https://github.com/getsentry/sentry-cocoa - MIT license; no MetricKit mention.
13. WebFetch https://github.com/nicklockwood/SwiftFormat/releases - latest 0.64.5 (31 Oct).
14. WebSearch "macOS 27 Human Interface Guidelines design 2026" - Liquid Glass revision, design kits, input guidance.
15. WebSearch "Parallels Desktop Linux Coherence mode Wayland 2026" - Coherence for Linux unsupported; Wayland gap.
16. WebFetch https://chromium.googlesource.com/.../sommelier/README.md - architecture; no cross-domain or non-ChromeOS statement.
17. WebFetch https://docs.getutm.app/ - backends only; no version or license.
18. WebFetch https://developer.apple.com/documentation/metrickit - page body empty; general knowledge flagged as unverified.

Not yet done (time-boxed): fetch the HIG pages directly for macOS 27 materials, sidebar, and toolbar rules; waypipe via an alternate mirror; swift-snapshot-testing and sentry-cocoa license and release dates; UTM version and license via GitHub; FreeRDP RAIL docs.
