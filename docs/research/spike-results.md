# Phase 1 spike results

Machine: MacBook (Apple M4, 16 GB), macOS 27.0.1, Xcode 27.2. Date: 2026-10-31. All numbers from runs on this machine.

## Spike 1: guest boot (Virtualization.framework, direct kernel boot)
Reproduce: `make image` then `spikes/01-boot` (`vmboot <image-dir> <data.img>`).
- Guest: Alpine 3.23 aarch64, linux-virt 6.18.59 (4 KiB pages), our initramfs (erofs system disk read-only + tmpfs overlay), OpenRC.
- `VZVirtualMachine.start` returns in 126-181 ms.
- Kernel + initramfs reach OpenRC at about 250 ms after start; OpenRC `boot` runlevel done at about 500 ms; DHCP lease at about 840 ms. `networking` blocks the runlevel until about 2 s (to be made non-blocking).
- First boot formats the data disk (ext4 on a 20 GiB sparse file): +4.2 s once.
- Host process RSS about 23 MB before guest memory is touched. Idle guest RAM: not yet measured.
- System image: 257 MB erofs (uncompressed on disk; erofs lz4hc), kernel Image 36 MB, initramfs 5 MB.
- Finding: Alpine's `vmlinuz-virt` is an EFI zboot (gzip) image that VZLinuxBootLoader rejects (`VZErrorDomain Code=1`); the build decompresses it to a raw arm64 `Image` (`image/build.sh`).

## Spike 2: Flatpak in the guest (Alpine, Lima vz VM; same packages)
- `flatpak` 1.16.6 + bubblewrap work on Alpine/musl: GNOME Calculator installs in 16.6 s (runtime GNOME 51, about 2.4 GB on disk); the app starts in the sandbox (fails only for lack of a display in that test).

## Spike 3: display path (guest Smithay compositor -> vsock -> NSWindow)
- A Linux Wayland client (`foot`) appears as a native macOS window (screenshot confirmed: title bar, traffic lights, correct content).
- Input-to-frame latency measured in-process (host injects key press+release, measures time until the next frame message arrives; excludes display scanout and vsync): 75 samples, **p50 2.7 ms, p95 3.0 ms, max 63 ms**; average compressed frame payload 451 bytes (terminal damage only).
- Not measured yet: end-to-end photon latency, frame pacing under load, large-window throughput, HiDPI sharpness (needs a human look), popups, resize.
- Gotcha found: key events are dropped until the window is key and the app is active (guest keyboard focus follows `Configure.activated`); headless tests must activate the app.

## Facts gathered on the way
- Flathub aarch64 coverage: 3538 apps with aarch64 refs vs 4128 x86_64 (about 86%).
- Flathub repo key fingerprint 6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE (from the .flatpakrepo; to be pinned and re-verified).
