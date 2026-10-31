# 0004: Guest: Alpine Linux, direct kernel boot, read-only erofs system disk

Date: 2026-10-31. Status: accepted.

## Context
Flatpak apps bring their own glibc runtimes, so the host distro's libc does not matter. We need fast boot, small image, 4 KiB pages (Rosetta/Venus constraints are reported), and a reproducible build.

## Decision
- Alpine 3.23 aarch64, `linux-virt` kernel (4 KiB pages; virtio balloon, free page reporting, virtiofs, vsock, virtio-gpu drivers present in config: measured).
- Boot: VZLinuxBootLoader with our own `Image` (decompressed from Alpine's EFI zboot gzip) + custom initramfs; no firmware, no bootloader.
- Disks: `system.erofs` (read-only, lz4hc) under a tmpfs overlay; a separate `data.img` (sparse ext4, formatted on first boot) holds /home and Flatpak. Reset = delete data.img; system update = replace system.erofs.
- Build: `image/build.sh` runs on any aarch64 Alpine (CI runner or a Lima VM via `make image`), pinned to the 3.23 branch. Output carries SHA256SUMS; releases publish the artifacts.

## Not bit-for-bit reproducible
apk repositories drop old package versions, so rebuilds pick up point updates. We pin the branch and record the resulting package list in the release notes; the shipped artifact is what users verify by checksum.

## Consequences
musl host libc is irrelevant to apps but matters for guest-side Rust code (static musl builds work: crosswindd is a native musl binary).
Revisit when: Alpine drops 4 KiB kernels or a required guest component is glibc-only and unfixable.
