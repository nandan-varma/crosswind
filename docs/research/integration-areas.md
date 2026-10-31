# Crosswind: integration areas research (Linux GUI apps in a Virtualization.framework arm64 VM on macOS 27)

Research date: 2026-10-31. Method: WebSearch and WebFetch only. Web content treated as data.

Verification caveat: most developer.apple.com pages returned only their title to WebFetch (no body text). Anything attributed to an Apple page below is either (a) from a search snippet that quoted the page, or (b) marked UNVERIFIED. Items from blogs, forums, and READMEs are labelled as secondary.

---

## Facts

### Apple platform and Virtualization.framework

- **WWDC26 session 224 "Expand the capabilities of your Virtualization app" exists.** Per secondary summaries, macOS 27 lets host apps implement their own virtio devices (custom virtio device API, reported as VZCustomVirtioDevice), adds USB accessory passthrough via a new Accessory Access framework, and adds vmnet-based custom networking and port forwarding. Some features require a macOS 27 host, and some also require a macOS 27 guest.
  - https://developer.apple.com/videos/play/wwdc2026/224/ (access 2026-10-31; search snippet only, video content not fetched)
  - https://heymsk.com/wwdc26/0224-expand-the-capabilities-of-your-virtualization-app/ (access 2026-10-31, secondary)
- **A community report shows custom virtio with standard device ID 16.** RiftVM exposed a virtio-gpu device (device 16) so Linux's virtio_gpu driver binds, with VirGL 3D acceleration.
  - https://medium.com/@everettjf/riftvm-running-3d-accelerated-omarchy-on-a-mac-with-macos-27s-custom-virtio-3f845e1dd08e (access 2026-10-31, secondary)
- **Regression reported on macOS 27.0.1.** A guest write to an unmapped physical address crashes com.apple.Virtualization.VirtualMachine with EXC_BREAKPOINT; macOS 26 silently ignored it. The same report found no Linux VM failures under Lima on macOS 27.
  - https://github.com/vergil-project/.github/issues/402 (access 2026-10-31, secondary)
- **Rosetta in Linux VMs (Apple doc, title only).** Apple's page "Running Intel Binaries in Linux VMs" exists. Its body was not retrievable. Per the search snippet, it says Rosetta is usable from ARM Linux VMs on Apple silicon with macOS 13+, and does not support bootstrapping or installing Intel Linux distributions.
  - https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms (access 2026-10-31; body UNVERIFIED)
- **WWDC23 session 10007 says Rosetta in Linux VMs uses the same technology as macOS, with a runtime caching daemon added in Sonoma.**
  - https://developer.apple.com/videos/play/wwdc2023/10007/ (access 2026-10-31; search snippet only)

### Rosetta 4 KiB page-size requirement

- **Not confirmed by any Apple primary source found.** Secondary claims:
  - A Hacker News commenter says Rosetta's userspace runs in 4K mode and XNU had to be reworked.
    - https://news.ycombinator.com/item?id=30733481 (access 2026-10-31, secondary, forum)
  - A gist says Asahi Linux defaults to 16K pages and the Rosetta binary requires a 4K-page kernel.
    - https://gist.github.com/federunco/f2bde2e25342c6284b68ce4ecf305e5d (access 2026-10-31, secondary)
- **Venus page-size conflict.** A Mac-specific PR says macOS pages are 16 KiB while Venus aligns guest allocations to 4 KiB, which breaks stock Mesa Venus on Mac. libkrun maintainers carry patches (copr slp/mesa-libkrun-vulkan).
  - Source cited in a search summary; PR link not fetched (UNVERIFIED as primary).
- **Consequence for the design:** Rosetta and Venus both have 4 KiB-vs-16 KiB page-size constraints on macOS hosts. The guest kernel page size is the open question, and it is UNKNOWN for a macOS 27 Virtualization.framework arm64 Linux guest.

### Virtualization.framework entitlements and sandbox

- **com.apple.security.virtualization.** Secondary general knowledge: Boolean entitlement for VZVirtualMachine; sandboxed apps (including Mac App Store builds) use it alongside com.apple.security.app-sandbox. The Apple doc body was not retrievable.
  - https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.virtualization (access 2026-10-31; body UNVERIFIED)
- **com.apple.vm.networking.** Not verified as a public Apple entitlement. Secondary belief: restricted, granted on request. UNKNOWN.
- **Hardened runtime.** A secondary source says Apple's notary service refuses binaries built without hardened runtime (codesign --options runtime).
  - https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/ (access 2026-10-31, secondary, dated)
- **Helper processes in sandbox.** Helpers need com.apple.security.inherit to inherit App Sandbox rules.
  - https://developer.apple.com/forums/thread/120647 (access 2026-10-31, forum)
- **Mac App Store permissibility of Virtualization.framework inside the sandbox.** UNKNOWN as verified. A forum thread about a similar app indicates the sandbox is workable but developers avoid temporary-exception entitlements. Verify against App Review Guidelines and the current App Sandbox docs before committing.

### Sparkle

- **Latest release: 2.10.1 ("Golden Gate Bump"), marked Latest, published 25 Oct (year not shown on the page).**
  - https://github.com/sparkle-project/Sparkle/releases/latest (access 2026-10-31)
- **Minimum macOS 12.0.** Release notes say Xcode 27 drops older deployment targets. Appcasts should carry sparkle:minimumSystemVersion 12.0 if not auto-generated.
  - Same URL as above.
- **CocoaPods support dropped** in 2.10.1.
  - Same URL as above.
- **EdDSA signing.** The repo states updates are verified via EdDSA signatures and Apple code signing. Signed feeds are validated as of 2.9. Key rotation is allowed when changing either the code-signing cert or the EdDSA key, not both.
  - https://github.com/sparkle-project/Sparkle (access 2026-10-31, README via search summary)
  - https://sparkle-project.org/documentation/security-and-reliability/ (access 2026-10-31, search snippet)
- **DSA deprecated** since Sparkle 1.27.3. Passing the EdDSA private key as a CLI argument is deprecated since 2.2.2.
- **License:** UNVERIFIED in this session. Believed MIT; confirm on the repo.

### Mesa Venus and virglrenderer

- **Host Vulkan requirements (Linux):** Vulkan 1.1 and VK_KHR_external_memory_fd. Tested drivers include ANV, RADV, NVIDIA, Turnip, PanVK, Lavapipe. Venus "is not expected to work on all drivers meeting the requirements."
  - https://docs.mesa3d.org/drivers/venus.html (access 2026-10-31)
- **Guest kernel:** needs virtio-gpu params VIRTGPU_PARAM_CONTEXT_INIT, RESOURCE_BLOB, etc.; typically 5.16+ or backported.
  - Same URL.
- **Build flag:** virglrenderer requires -Dvenus=true.
  - Same URL.
- **macOS/MoltenVK:** the Mesa Venus page does NOT mention macOS. Status on macOS is UNKNOWN from this source.
  - Same URL.
- **Known limitation:** Venus depends on implementation-defined behavior for host-visible memory mapping; long-term fix is a planned Vulkan extension.
  - Same URL.
- **Secondary, libkrun path:** libkrun exposes virtio-gpu with Venus; virglrenderer forwards to MoltenVK, which maps Vulkan to Metal. Red Hat reports about 40x speedup for AI inference in macOS containers, and llama.cpp Vulkan at about 77% of Metal.
  - https://developers.redhat.com/articles/2025/06/05/how-we-improved-ai-inference-macos-podman-containers (access 2026-10-31, secondary, about 17 months old)
  - https://github.com/fxgl/steamac (access 2026-10-31, secondary; libkrun + Venus + MoltenVK for SteamOS on Apple silicon)
- **KosmicKrisp**, Mesa's Vulkan-on-Metal 4 driver, is reported as experimental on macOS 26+.
  - Source: search summary only (UNVERIFIED beyond that).

### Xwayland and Wayland protocols

- **xwayland-satellite:** MPL-2.0. Provides rootless Xwayland to any Wayland compositor that implements xdg_wm_base and viewporter. Optional fractional-scale support. Requires Xwayland, xcb, xcb-util-cursor. It does not state clipboard, text-input, or drag-and-drop support on the page fetched.
  - https://github.com/Supreeeme/xwayland-satellite (access 2026-10-31)
- **wp-fractional-scale-v1** is paired with wp_viewport. Mutter added XWayland fractional-scale support in early 2024 (GNOME 46+). Known issue: fractional scales can round up and produce oversized windows in xwayland-satellite.
  - Search summary (access 2026-10-31); no primary protocol XML fetched.
- **text-input-v3:** XWayland bridges XIM to zwp_text_input_v3, per a secondary book chapter. Details UNKNOWN.
  - https://github.com/jreuben11/linux-graphics-stack-book (access 2026-10-31, secondary)

### FEX-Emu

- **FEX:** MIT. Runs x86 apps on ARM64 Linux, comparable to qemu-user and box64. Requires ARMv8.0-a+ with FEAT_FP and FEAT_CRC32. Tested on Arch, Fedora, openSUSE, Ubuntu 22.04–25.04. The page does not mention macOS, Apple silicon VMs, or 4K page size.
  - https://github.com/FEX-Emu/FEX (access 2026-10-31)

### Vendored projects not yet checked

- Waypipe, Sunshine, virtio-snd, PipeWire, xdg-desktop-portal, StatusNotifier, and Accessory Access APIs were NOT researched in this session. See Search log.

---

## Assumptions

1. The target is Linux arm64 guests on Apple silicon hosts running macOS 27. x86 Linux binaries are run through emulation inside the guest, not as native Linux VMs.
2. The app ships outside the Mac App Store first. MAS distribution is a second decision.
3. Custom virtio devices (macOS 27 API) are available on target hosts. Minimum host version is macOS 27 for this design.
4. The Virtualization.framework guest is Linux with a 4K-page kernel, because Rosetta and Venus both constrain page size. If 16K pages are used, Rosetta usage is blocked (UNVERIFIED).
5. Pixel-perfect HiDPI requires host-side scaling that the compositor understands. The host is macOS (NSScreen backingScaleFactor), not a Wayland compositor.
6. Sparkle continues to serve as the update framework for direct distribution.

---

## Opinions

These are judgments, not verified facts.

- **GPU:** Start with virtio-gpu via Venus (libkrun or the custom-virtio route) for 3D apps. Fall back to virgl or CPU (llvmpipe, software GL) for compatibility. Expect Venus on macOS to be experimental and to need patched Mesa and libkrun builds. Treat the 4K/16K mismatch as the top risk.
- **Frame pacing and tearing:** Use host CAMetalLayer/CADisplayLink vsync per window. Expect per-window buffer copies to be the main cost. Tearing control is best on the host side; the guest can use the Wayland frame callback.
- **Xwayland:** Use xwayland-satellite (MPL-2.0) rather than custom rootless code. Its fractional-scale rounding issue needs a workaround in the host compositor.
- **x86 translation:** Rosetta is the fastest option if the page-size constraint is met, but the path is unofficial for Linux guests. FEX-Emu is more portable. qemu-user is the most mature fallback. Plan for FEX-Emu with Rosetta as an optional accelerator, and verify Rosetta's current Linux-guest status with Apple before committing.
- **HiDPI:** Render at backing scale on the host; let the guest use integer scale plus wp-fractional-scale for fractional values.
- **IME:** text-input-v3 is the right target; expect rough edges bridging macOS NSTextInputClient and the guest.
- **Audio:** PipeWire inside the guest, bridged to macOS CoreAudio over vsock, is likely more reliable than virtio-snd alone. Unverified.
- **Notifications, tray, file chooser:** Build a thin xdg-desktop-portal backend that calls NSOpenPanel and UNUserNotificationCenter. Tray icons via StatusNotifier map to NSStatusItem; both need work.
- **Packaging:** Hardened runtime plus com.apple.security.virtualization is required for direct distribution. Keep the MAS question open until App Review feedback is known.
- **Updates:** Sparkle 2.x with EdDSA plus Developer ID is a mature default for direct distribution. Confirm the 2.10.1 release date year before citing it.
- **Memory ballooning and free page reporting:** Use the virtio-balloon device with free page reporting. Unverified in this session.

---

## Search log

Queries and fetches run on 2026-10-31:

1. WebSearch: Rosetta Linux VM Virtualization framework Apple documentation 4KB page size.
2. WebSearch: Sparkle macOS updater latest release EdDSA signing.
3. WebSearch: Virtualization framework com.apple.security.virtualization entitlement hardened runtime Mac App Store sandbox.
4. WebSearch: virtio-gpu Venus Vulkan macOS MoltenVK libkrun Mesa.
5. WebSearch: Wayland wp-fractional-scale-v1 text-input-v3 protocol Xwayland rootless macOS.
6. WebFetch: developer.apple.com Running Intel Binaries in Linux VMs (title only).
7. WebFetch: github.com/sparkle-project/Sparkle/releases/latest (succeeded).
8. WebFetch: developer.apple.com/documentation/virtualization (title only).
9. WebFetch: docs.mesa3d.org/drivers/venus.html (succeeded).
10. WebFetch: developer.apple.com com.apple.security.virtualization (title only).
11. WebSearch: WWDC26 Virtualization framework macOS 27 new features Linux guest.
12. WebFetch: github.com/Supreeeme/xwayland-satellite (succeeded).
13. WebFetch: github.com/FEX-Emu/FEX (succeeded).

Not done (time budget): WebSearch/WebFetch on libkrun, virgl, Waypipe, Sunshine, PipeWire over vsock, virtio-snd, xdg-desktop-portal backends, StatusNotifier, text-input-v3 spec XML, drag-and-drop and clipboard bridges, webcam/Bluetooth/USB (Accessory Access), VPN/sleep-wake networking, free page reporting, qemu-user status, and Apple App Review rules for VM apps. All of these remain UNKNOWN in this document.

Apple developer pages were not readable through WebFetch in this session. Re-check WWDC26 session 224 and the Virtualization and entitlement pages in a browser before relying on any Apple API or entitlement claim.
