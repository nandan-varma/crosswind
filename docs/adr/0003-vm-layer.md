# 0003: VM layer: Virtualization.framework directly

Date: 2026-10-31. Status: accepted.

## Options
Lima (vz driver), Apple `container`/Containerization, libkrun/krunkit, raw Virtualization.framework.

## Decision
Use Virtualization.framework directly, behind one small `GuestVM` class.
- Lima and `container` do not expose macOS 27 custom virtio devices, direct kernel boot control, our vsock channels or snapshot control without wrapping; we would drive their CLIs and parse output.
- libkrun's 2.0 branch breaks the 1.x API and macOS 27 support is unverified.
- The API surface we need is small and first-party: VZLinuxBootLoader, virtio-blk, virtio-net (NAT), virtio-vsock, balloon, entropy, console (measured: VM start 126-181 ms).

## Consequences
We write and own the VM lifecycle code (about 110 lines). Lima remains a development-time tool for building the guest image on a Mac (not shipped, not a second runtime path).
Revisit when: Virtualization.framework regressions block us (a macOS 27.0.1 crash on unmapped guest writes is reported, not reproduced here).
