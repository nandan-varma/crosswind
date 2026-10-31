# VM layers for arm64 Linux guests on macOS 27 (Apple silicon)

Research date: 2026-10-31. Status values come from the sources listed; anything not verified is marked `unknown`.

## Facts

Access date for every source below: 2026-10-31.

### 1. Raw Virtualization.framework (macOS 27)

- **Custom virtio devices (new in macOS 27).** `VZCustomVirtioDevice`, `VZCustomVirtioDeviceConfiguration`, `VZCustomVirtioDeviceDelegate`, attached via `VZVirtualMachineConfiguration.customVirtioDevices`. Supported guests: Linux. The guest needs a custom driver for the device.
  - Source: https://developer.apple.com/videos/play/wwdc2026/224/ (WWDC26 session 224, "Expand the capabilities of your Virtualization app")
  - Source: https://developer.apple.com/documentation/virtualization/vzcustomvirtiodeviceconfiguration.md
  - Single-source report (third-party blog, not verified against Apple docs): custom devices get no callback when the guest writes device config, which blocks spec-compliant dynamic virtio-input. Source: https://medium.com/@everettjf/riftvm-running-3d-accelerated-omarchy-on-a-mac-with-macos-27s-custom-virtio-3f845e1dd08e
- **virtio-gpu / 3D / Venus.** Not provided by Apple. Community project `vzgpu` builds a Venus virtio-gpu on the custom virtio API. The author reports a passing Venus check on a Fedora guest under macOS 27.2. Single-project claim, unverified.
  - Source: https://github.com/Quiet-Wolfe/vzgpu
  - Source: https://github.com/utmapp/UTM/issues/7921 (UTM tracking 3D acceleration via the custom virtio feature)
- **USB passthrough (new in macOS 27).** Accessory Access: `AAUSBAccessoryManager`, `VZUSBPassthroughDevice`, and a USB controller. Supports hot plug and works for macOS and Linux guests. The host app needs the "Claim USB Accessory" capability. VM changes must run on the VM's queue.
  - Source: https://developer.apple.com/videos/play/wwdc2026/224/
- **vmnet networking.** `VZVmnetNetworkDeviceAttachment` with DHCP and TCP/UDP port forwarding. Stated as available from macOS 26. Networks are not persisted across app quit.
  - Source: https://developer.apple.com/videos/play/wwdc2026/224/
- **DiskImageKit (new in macOS 27).** Layered sparse images (ASIF/raw base, cache, overlay). Upper layers must be ASIF. Cloned VMs must duplicate aux storage and EFI variable store files.
  - Source: https://developer.apple.com/videos/play/wwdc2026/224/
- **Other macOS 27 items.** EFI Secure Boot for Linux VMs. Metal argument buffers and indirect command buffers for macOS guests. macOS guest provisioning options (macOS guests only).
  - Source: https://developer.apple.com/videos/play/wwdc2026/224/
- **Rosetta in Linux VMs.** Apple's doc says macOS 27 integrates Intel binary translation directly, so no separate Rosetta install is needed. Apple doc title: "Running Intel binaries in Linux VMs". Reported (third-party tracker, Parallels blog): Rosetta is not auto-restored after an upgrade, and broader Rosetta support disappears in macOS 28. Not confirmed on Apple's release notes page.
  - Source: https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms.md
  - Source: https://www.parallels.com/blogs/macos-27-golden-gate-parallels-desktop/
  - Source: https://github.com/logical-minds-foundry/.github/issues/361 (tracker; says release notes lack a macOS 27 section; conflicts with the Apple doc, unresolved)
- **Memory ballooning, suspend/resume, save/restore state, virtiofs, vsock, SPICE clipboard agent (`VZSpiceAgentPortAttachment`).** Not found in WWDC26 session 224 or in any search result. Status: `unknown` for macOS 27 changes. These APIs are long-standing Virtualization.framework features, but I did not verify their macOS 27 status.

### 2. Lima vz driver

- License: Apache-2.0. Repo `lima-vm/lima`, not archived. Source: https://api.github.com/repos/lima-vm/lima
- Last push: 2026-10-30. Source: https://api.github.com/repos/lima-vm/lima
- Latest release: v2.2.1, published 2026-10-03, not a prerelease. Source: https://api.github.com/repos/lima-vm/lima/releases/latest
- Pre-release in progress: v2.3.0-beta.1 (host block device attach, `audio.microphone`). Source: https://github.com/lima-vm/lima/releases
- Open issues (GitHub API `open_issues_count`, which counts issues and PRs): 500. Source: https://api.github.com/repos/lima-vm/lima
- Driver history: v1.0.0 made VZ the default driver. v2.0.0 added an experimental plugin subsystem and an experimental krunkit driver. Source: https://github.com/lima-vm/lima/releases
- Maintainers and bus factor: `unknown` (not checked).
- macOS 27 support: `unknown` (no release notes found that mention macOS 27).
- Limitations: no macOS 27 custom-virtio, USB, or DiskImageKit integration found in the sources.

### 3. Apple `container` / Containerization

- `apple/containerization` is the Swift package. `apple/container` is the CLI built on it. Both Apache-2.0 per the usual project license; license confirmed only for the GitHub API result below.
- `apple/container` latest release: 1.6.1, published 2026-10-23. Notable changes: fixes signal forwarding; renames the Kubernetes feature to `container cluster` (breaking CLI change); fixes cluster creation races; infers platform from OCI image. Source: https://api.github.com/repos/apple/container/releases/latest
- Requires macOS 26 (per search snippet). Source: https://github.com/apple/container/releases
- Containerization `apple/containerization` last push, license, open issues: `unknown` (not fetched).
- macOS 27 support: `unknown`. Release notes do not mention macOS 27.
- Limitations: source stability promised only within minor versions; CLI minor releases may include breaking changes until 1.0.0. Source: https://github.com/apple/containerization (via search snippet)

### 4. libkrun / krunkit

- `containers/krunkit` (now `libkrun/krunkit`): Apache-2.0, not archived, last push 2026-10-14, 22 open issues. Source: https://api.github.com/repos/containers/krunkit
- krunkit latest release: v1.3.2 (tagged "July 3" per search snippet; year not confirmed). Source: https://github.com/containers/krunkit/releases
- `libkrun/libkrun`: Apache-2.0, not archived, last push 2026-10-30, 126 open issues. Source: https://api.github.com/repos/libkrun/libkrun
- libkrun `main` is now 2.0, which breaks 1.x API/ABI. Source: https://github.com/libkrun/libkrun (search snippet)
- macOS: krunkit requires macOS 14 or newer. Source: https://github.com/containers/krunkit (search snippet)
- macOS 27 support: `unknown`.
- Limitations: needs the EFI flavor of libkrun on macOS. Installed via Homebrew tap `slp/krun` (search snippet; a second source names `slp/krunkit`, so the tap name is unverified).

### 5. Other options

- Not researched in depth. `utmapp/UTM` tracks macOS 27 custom-virtio 3D work (issue #7921). Source: https://github.com/utmapp/UTM/issues/7921
- Parallels Desktop covers macOS 27 host compatibility. Source: https://www.parallels.com/blogs/macos-27-golden-gate-parallels-desktop/ (not checked for arm64 Linux guest support)

## Assumptions

- The Lima v2.2.1 and apple/container 1.6.1 release dates are correct as returned by the GitHub API.
- The `vzgpu` Venus result is reproducible; I did not run it.
- Apple's WWDC26 session 224 is representative of the full macOS 27 Virtualization feature set. Features not in that session may still exist but were not verified.
- "Last commit date" is approximated by GitHub's `pushed_at`, which tracks the last push to any branch.

## Opinions

- For a macOS 27 arm64 Linux guest that needs GPU acceleration, the custom virtio API plus a custom driver is the only path visible in the sources. It is new, one-off, and carries maintenance cost.
- Lima is the most mature orchestration layer around the vz driver. Its large open-issue count is partly PRs and should not be read as a health alarm on its own.
- Apple `container` is a good fit for OCI container workloads. It is a weak choice for a VM-level product because it is tied to its own container runtime model and does not expose the custom virtio path.
- Pin Rosetta and macOS 27 behavior assumptions to tested builds. The sources disagree on Rosetta persistence across upgrades.

## Search log

Queries tried:
- "macOS 27 Virtualization framework VZCustomVirtioDevice WWDC26" — used; surfaced WWDC26 session 224 and Apple API pages.
- "Lima vz driver releases github lima-vm/lima" — used; release history. Rejected: a fork (`hftsin/lima`).
- "apple/container github releases Containerization framework" — used; repo list. Rejected: unrelated forks (`fairuzan`, `makhov`, `dictav`).
- "containers/libkrun krunkit github releases macOS" — used; krunkit/libkrun repos. Rejected: `erofs/containers-libkrun` and `Mac-Neutron/libkrun` (forks).
- "macOS 27 Virtualization Linux guest virtio-gpu Venus Rosetta memory balloon save restore release notes" — partly used; found Rosetta and vzgpu, no balloon/save-restore coverage.
- Direct GitHub API fetches for repo and release metadata — used; primary source for dates, license, and issue counts.
- WWDC26 session 224 fetch — used; no mention of GPU, balloon, save/restore, virtiofs, vsock, or SPICE.

Not yet done: Apple developer release notes for macOS 27 (the primary source for balloon/save-restore/Rosetta), Lima maintainer list, apple/containerization repo stats, libkrun maintainers.
