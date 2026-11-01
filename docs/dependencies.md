# Dependencies

Audit date: 2026-10-31. Sources: `guest/Cargo.toml`, `guest/crosswindd/Cargo.toml`, `guest/Cargo.lock`, `Packages/CrosswindKit/Package.swift`, `project.yml`, `image/packages`, `image/build.sh`, `Makefile`. Upstream facts were fetched with `gh api` (GitHub), the crates.io API, and `pkgs.alpinelinux.org` (v3.23, aarch64). Nothing here comes from memory.

Column notes: "Last push" is GitHub `pushed_at`. "Open issues" is GitHub `open_issues_count`, which also counts open pull requests. "Recent contributors" is the number of distinct commit authors in the 12 months before the audit date, taken from the first 100 commits returned by the API. "All-time" counts are capped at the first API page of 100.

## License flags

- **No incompatible direct dependency found.** Every direct dependency is MIT, Apache-2.0, or MPL-2.0, and all three can be combined into an AGPL-3.0-or-later distribution. Apache-2.0 code is one-way compatible with AGPLv3. MPL-2.0 lists AGPL-3.0 as a Secondary License, so it can be combined as a Larger Work. The rejected GPL-3.0 `waypipe` is not linked into this project.
- **The guest image ships GPL-2.0 and GPL-2.0-or-later code, plus LGPL-2.1.** This applies to `linux-virt` (the kernel), `busybox`, `busybox-openrc`, `mkinitfs`, `alpine-baselayout`, `iproute2`, `hicolor-icon-theme`, and LGPL packages such as `bubblewrap`, `flatpak`, `pipewire`, and `wireplumber`. These are separate programs in an aggregate image, so AGPL does not spread to them. Any release that distributes the image must still provide the corresponding source (or a written offer for it) for every GPL and LGPL component, and must include their license texts. This is an open obligation, not yet implemented in the release process. Verify before the first Developer ID release.
- **Alpine packages are not pinned.** `image/build.sh` installs whatever `v3.23` main and community provide at build time. The license column below reflects the current v3.23 metadata. Re-check it when the image is rebuilt.
- **Sparkle (2.10.1, shipped in the store app)** has no single SPDX license on GitHub (reported as NOASSERTION). Its LICENSE file is a composite: MIT for Sparkle's own code, plus MIT and BSD-style notices for bundled third-party code. The notices ship in the app as `Contents/Resources/Sparkle-LICENSE.txt` (copied from the package's LICENSE).
- **pixman crate:** GitHub reports no license for `cmeissl/pixman-rs` and the repository has no LICENSE file at the root. The `pixman/Cargo.toml` and crates.io both say MIT. Treat this as MIT with a metadata gap, and raise it upstream.

## Summary

| Area | Count | Notes |
|---|---|---|
| Rust direct deps (crosswindd) | 6 runtime + 1 build (+ Smithay) | `prost-build` is build-only |
| Rust transitive crates | 103 | 104 entries in `guest/Cargo.lock`, minus the `crosswindd` package itself |
| Swift direct deps | 3 packages (swift-protobuf, swift-argument-parser, Sparkle) | Declared in `Package.swift` and `project.yml`; Sparkle is in the app target only |
| Dev tools | XcodeGen, SwiftLint, swift-format (Xcode), Lima | Not shipped |
| Guest image packages | 31 listed in `image/packages` | Table below |

## Direct dependencies

### Sparkle (Swift package, `Sparkle`)

- **Why:** signed in-app updates for the Developer ID build (`docs/adr/0001-license-and-name.md`, which rules out the Mac App Store).
- **Used by:** the store app only (`App/Store/Updates/AppUpdater.swift`, the Crosswind target in `project.yml`). `CrosswindKit` does not depend on it. The embedded `Sparkle.framework` and its XPC services and `Autoupdate` are signed by `scripts/release.sh`.
- **Version pinned:** exact **2.10.1** in `project.yml` (`exactVersion`). Latest GitHub release: 2.10.1 (2026-10-25), checked with `gh release list -R sparkle-project/Sparkle`.
- **License:** see the license flags above. Notices ship in the app.
- **Last push:** 2026-10-25. **Open issues:** 11. **Recent contributors:** 14 (all-time 100+). Figures from the audit date.
- **macOS 27 / Apple silicon:** the package builds for the macOS 27 target on arm64 and the release export passes the signature checks. An end-to-end update on macOS 27 has not been run yet.
- **Security model:** updates are signed with an EdDSA (Ed25519) key. `SUPublicEDKey` is in `project.yml`; the private key is in the release machine's login keychain. DSA is not used (deprecated by Sparkle).
- **Privacy:** automatic checks are on by default; `SUEnableSystemProfiling` is `NO`, so Sparkle does not send a system profile.
- **Alternatives rejected:** Mac App Store updates (excluded by the license ADR); Sparkle 1.x (superseded; no EdDSA); DSA signing (deprecated); a hand-written updater (would have to implement signature checks, download, and safe install and relaunch itself).
- **Replacement plan / cost:** Medium. Remove the package, `AppUpdater.swift`, the `SU*` keys, and the appcast step in `release.sh`. Users would then download new versions by hand. The EdDSA private key must be backed up: losing it stops updates for every installed copy.

### Smithay (Rust, `smithay`, git)

- **Used by:** `guest/crosswindd` (Wayland compositor core). Features: `wayland_frontend`, `desktop`, `renderer_pixman`, with `default-features = false`.
- **Version pinned:** git rev `f581531d479cf2e3307bafb913c5d2bb12860bb3`. This is **not a released crate version**. The lock file resolves it as `smithay 0.7.0`, which is the crate version number in that commit's `Cargo.toml`. The crates.io release `0.7.0` is from 2025-06-24. The pinned rev is 510 commits ahead of `v0.7.0`, and its commit date is 2026-10-29.
- **License:** MIT (`Cargo.toml` at the pinned rev, and crates.io). Compatible with AGPL-3.0-or-later.
- **Last release:** crates.io 0.7.0, 2025-06-24. GitHub latest release is also v0.7.0.
- **Last push:** 2026-10-29. **Open issues:** 288.
- **Recent contributors:** 40 (all-time 100+).
- **macOS 27 / Apple silicon:** not relevant. Smithay runs only in the Linux guest. The guest is aarch64 Alpine, which is musl. A musl build of this rev is implied by `image/build.sh` but not verified in this audit.
- **Alternatives rejected:** wlroots-style C bindings (`wlroots-rs`) and writing the protocol layer by hand. Not recorded in repo docs; guest architecture choice is in `docs/research/guest-integration.md`.
- **Risk:** a git dependency on an unreleased revision. Builds depend on GitHub availability, and the revision is not reproducible from crates.io.
- **Replacement plan / cost:** Move to the next crates.io release when one ships that contains the needed fixes (the rev includes at least one GLES fix). Cost: medium. Vendoring the rev is the fallback. Expect API churn between 0.7.0 and the rev.

### prost (Rust, `prost`)

- **Used by:** `crosswindd`, for the protobuf runtime types in the wire protocol (`proto/display.proto`, `proto/control.proto`).
- **Version pinned:** `0.13` in `Cargo.toml`, resolved to **0.13.5** in `Cargo.lock`. Latest on crates.io is **0.14.4** (2026-06-07). Moving to 0.14 is a minor-version bump with API changes to check.
- **License:** Apache-2.0. Compatible with AGPL-3.0-or-later (one-way).
- **Last release:** 0.14.4, 2026-06-07 (crates.io and GitHub). **Last push:** 2026-10-27. **Open issues:** 251.
- **Recent contributors:** 14 (all-time 100+).
- **macOS 27 / Apple silicon:** not relevant (guest only). Pure Rust, no platform code.
- **Alternatives rejected:** none recorded in repo docs.
- **Replacement plan / cost:** Low for a swap to another protobuf crate, but both sides (Swift and Rust) share `.proto` files, so a change needs regenerating both sides.

### prost-build (Rust, `prost-build`, build dependency)

- **Used by:** `guest/crosswindd/build.rs`, which compiles `proto/display.proto` and `proto/control.proto`.
- **Version pinned:** `0.13` in `Cargo.toml`, **0.13.5** in the lock file. Latest is 0.14.4 (same release as prost).
- **License:** Apache-2.0. Compatible.
- **Last release / push:** same repo as prost (tokio-rs/prost); 2026-06-07 / 2026-10-27.
- **Build requirement:** `protoc` must be on `PATH` (or set `PROTOC`). Checked in the 0.13.5 crate source (`src/lib.rs`). The Lima build VM must install `protobuf`. Not yet listed in `image/build.sh`.
- **macOS 27 / aarch64-musl:** build host only. It runs on the Lima Alpine VM.
- **Alternatives rejected:** a checked-in pre-generated `.rs` file (not chosen; not recorded elsewhere).
- **Replacement plan / cost:** Same as prost. Also add `protobuf` to the Alpine build environment if it is not already present.

### lz4_flex (Rust, `lz4_flex`)

- **Used by:** `crosswindd`, for LZ4 frame compression of pixel data. Features: `safe-encode` and `safe-decode` with `default-features = false`, so the crate runs without `unsafe` code paths.
- **Version pinned:** `0.11` in `Cargo.toml`, **0.11.6** in the lock file. Latest on crates.io is **0.14.0** (2026-07-14). GitHub's "latest release" tag is 0.13.1 (2026-05-31), so the two sources disagree. The crate on crates.io is the authority for versions.
- **License:** MIT. Compatible.
- **Last push:** 2026-10-25. **Open issues:** 38.
- **Recent contributors:** 9 (all-time 30).
- **macOS 27 / Apple silicon:** not relevant. Runs in the guest. Pure Rust, aarch64 is supported.
- **Alternatives rejected:** `lz4` (C bindings, extra C build dependency); `zstd` (heavier, not chosen for the pixel path). Not recorded elsewhere.
- **Replacement plan / cost:** Moving from 0.11 to 0.14 is a major version bump. Expect API changes in the frame encoder. Cost: low to medium, bounded by one module.

### vsock (Rust, `vsock`)

- **Used by:** `crosswindd`, for the AF_VSOCK transport to the macOS host (3 source files reference it).
- **Version pinned:** `0.5` in `Cargo.toml`, **0.5.4** in the lock file. Latest 0.5.4 (crates.io, 2026-03-30). No GitHub Release object exists (the API returns 404). The latest tag is `v0.5.4`.
- **License:** Apache-2.0. Compatible.
- **Last push:** 2026-10-29. **Open issues:** 4.
- **Recent contributors:** 3 (all-time 9). **Bus factor is low.**
- **macOS 27 / Apple silicon:** the host side uses Virtualization.framework's vsock device, not this crate. This crate only runs in the guest. Works on aarch64 Linux.
- **Alternatives rejected:** raw `libc` socket calls (possible, more unsafe code). `tokio-vsock` (async, not needed in this design). Not recorded elsewhere.
- **Replacement plan / cost:** Low. Roughly 3 call sites. A fallback to `libc` directly is a small change if the crate stops being maintained.

### pixman (Rust, `pixman`, crate version 0.2.1)

- **Used by:** `crosswindd`, through Smithay's `renderer_pixman` feature (2 source files reference it directly).
- **Version pinned:** `0.2.1`, exact in both manifest and lock file. It is the latest crates.io release (2024-12-15).
- **License:** MIT per `pixman/Cargo.toml` and crates.io. The GitHub repo reports no license and has no root LICENSE file (see license flags).
- **Last push:** 2024-12-15. **Open issues:** 5. **Recent contributors:** 0 in the last 12 months (all-time 3). **Bus factor is very low and the crate is stale.** It links the system C library `libpixman` (MIT), which must be installed in the Alpine build environment.
- **macOS 27 / Apple silicon:** not relevant (guest only).
- **Alternatives rejected:** the GLES renderer path in Smithay (needs GPU, not in this guest). Not recorded elsewhere.
- **Replacement plan / cost:** Medium. The pixman renderer is the software rendering path for the guest; a replacement would be Smithay's own software renderer or the `renderer_glow` path with Mesa. Plan a spike before the next guest release if the crate or Smithay rev breaks.

### tracing (Rust, `tracing`)

- **Used by:** `crosswindd`, in 5 source files, for structured logs.
- **Version pinned:** `0.1` in `Cargo.toml`, **0.1.44** in the lock file. Latest is 0.1.44 (2025-12-18).
- **License:** MIT. Compatible.
- **Last push:** 2026-10-29 (repo `tokio-rs/tracing`). **Open issues:** 905 (includes PRs).
- **Recent contributors:** 35 (all-time 100+).
- **macOS 27 / Apple silicon:** not relevant.
- **Alternatives rejected:** `log` plus `env_logger` (no spans; not chosen). Not recorded elsewhere.
- **Replacement plan / cost:** Low. Very widely used; no replacement needed.

### tracing-subscriber (Rust, `tracing-subscriber`)

- **Used by:** `crosswindd`, with the `env-filter` feature. Used in 1 source file, for initialization.
- **Version pinned:** `0.3` in `Cargo.toml`, **0.3.23** in the lock file. Latest is 0.3.23 (2026-03-13).
- **License:** MIT. Compatible.
- **Last push / issues / contributors:** same repo as tracing (see above).
- **macOS 27 / Apple silicon:** not relevant.
- **Alternatives rejected:** `env_logger` (not chosen; not recorded elsewhere).
- **Replacement plan / cost:** Low. Only the initialization site depends on it.

### swift-protobuf (Swift package, `SwiftProtobuf`)

- **Used by:** `Packages/CrosswindKit` (`Display/FramedConnection.swift` and the generated `Generated/control.pb.swift`, `Generated/display.pb.swift`). Declared in `Package.swift` as `exact: "1.39.0"`.
- **Version pinned:** exact **1.39.0**, which is the latest release (GitHub, 2026-10-12).
- **License:** Apache-2.0. Compatible.
- **Last push:** 2026-10-29. **Open issues:** 64.
- **Recent contributors:** 19 (all-time 100+).
- **macOS 27 / Apple silicon:** the package targets `.macOS(.v27)` and is built for arm64 on the host. Compatible with the macOS 27 target.
- **Alternatives rejected:** hand-written binary encoding. Not recorded elsewhere.
- **Replacement plan / cost:** Medium. The generated Swift code would need regenerating with another generator, and the framing layer depends on the SwiftProtobuf API.

### swift-argument-parser (Swift package, `ArgumentParser`)

- **Used by:** `tools/crosswindctl` (the `crosswindctl` command-line tool, a `tool` target in `project.yml`). Pinned in `project.yml` as `exactVersion: 1.8.2`.
- **Version pinned:** exact **1.8.2**, which is the latest release (GitHub, 2026-06-04).
- **License:** Apache-2.0. Compatible.
- **Last push:** 2026-10-30. **Open issues:** 157.
- **Recent contributors:** 27 (all-time 100+).
- **macOS 27 / Apple silicon:** built for arm64 macOS 27 as part of the Xcode project.
- **Alternatives rejected:** hand-parsed `CommandLine.arguments`. Not recorded elsewhere.
- **Replacement plan / cost:** Low. Only `crosswindctl` depends on it.

### XcodeGen (dev tool, `xcodegen`)

- **Used by:** `make project` (`Makefile`, `xcodegen generate`). Generates `Crosswind.xcodeproj` from `project.yml`. The project file is not committed.
- **Version pinned:** **not pinned in the repo.** The Makefile calls whatever `xcodegen` is on `PATH`. Latest is **2.46.0** (GitHub, 2026-07-16).
- **License:** MIT. Not shipped.
- **Last push:** 2026-10-13. **Open issues:** 404.
- **Recent contributors:** 16 (all-time 100+).
- **macOS 27 / Apple silicon:** runs natively on arm64.
- **Alternatives rejected:** checking in `.xcodeproj` (not chosen; the Makefile and `project.yml` document this). Not recorded elsewhere.
- **Replacement plan / cost:** Low. Pin the version in a Brewfile or a Makefile check, or switch to a committed project file if XcodeGen stops working.

### SwiftLint (dev tool, `swiftlint`)

- **Used by:** `make lint` (`swiftlint lint --strict`), with `.swiftlint.yml`.
- **Version pinned:** **not pinned in the repo.** Latest is **0.65.1** (GitHub, 2026-08-21).
- **License:** MIT. Not shipped.
- **Last push:** 2026-10-16. **Open issues:** 540.
- **Recent contributors:** 16 (all-time 100+).
- **macOS 27 / Apple silicon:** runs natively on arm64.
- **Alternatives rejected:** none recorded.
- **Replacement plan / cost:** Low. Pin the version when the lint job runs in CI.

### swift-format (dev tool, `xcrun swift-format`)

- **Used by:** `make lint` and `make format` in the `Makefile`. Ships with Xcode, so there is no separate version pin.
- **License:** Apache-2.0 (Apple). Not shipped. Compatible.
- **Replacement plan / cost:** None needed.

### Lima (dev tool, `limactl`)

- **Used by:** the `cwbuild` VM (`Makefile`, `LIMA_VM ?= cwbuild`). It runs the Alpine aarch64 build of `crosswindd` and the guest image (`image/build.sh`).
- **Version pinned:** **not pinned in the repo.** Latest release is **v2.2.1** (GitHub, 2026-10-03). A newer prerelease `v2.3.0-rc.0` exists. Not used.
- **License:** Apache-2.0. Not shipped.
- **Last push:** 2026-10-30. **Open issues:** 500.
- **Recent contributors:** 16 (all-time 100+).
- **macOS 27 / Apple silicon:** it runs an aarch64 Alpine VM through Virtualization.framework on Apple silicon. This is the main reason it fits.
- **Alternatives rejected:** UTM (GUI-oriented; not scriptable the same way) and building on a remote Linux CI host only. Not recorded in repo docs.
- **Replacement plan / cost:** Medium. The Makefile targets use `limactl shell` and `limactl copy`. A switch to another aarch64 Linux VM would need those targets rewritten.

### Alpine Linux (guest distro, `v3.23`)

- **Used by:** the guest rootfs and kernel (`image/build.sh`, `ALPINE_BRANCH=v3.23`), with the `main` and `community` repos from `dl-cdn.alpinelinux.org`.
- **Version pinned:** branch `v3.23`. Packages float within this branch (no package pins). The branch's release date was not checked in this audit.
- **License:** per package (table below). `mkinitfs` is GPL-2.0-only and ships in the image. `apk` runs only on the build host and was not checked.
- **macOS 27 / Apple silicon:** the guest is aarch64, matching Apple silicon through Virtualization.framework.
- **Alternatives rejected:** Debian or Ubuntu (larger image, slower to build with `apk --root`). Not recorded in repo docs.
- **Replacement plan / cost:** Medium. Moving to another distribution means rewriting `image/build.sh` and the OpenRC service scripts.

### erofs-utils (build-host tool, `mkfs.erofs`)

- **Used by:** `image/build.sh`, which runs `mkfs.erofs -zlz4hc -T0` to build `system.erofs`. The tool is **not installed in the guest** (it is not in `image/packages`). It runs inside the Lima VM.
- **Version pinned:** **not pinned in the repo.** Latest tag is **v1.9.4** (commit 2026-08-19). GitHub returns no Release object for this repo (`/releases/latest` returns 404). Alpine's community package builds from the same codebase.
- **License:** GPL-2.0 (with MIT parts, per the `LICENSES/` directory). Alpine lists `GPL-2.0-or-later`. This is a build tool that does not link into the output image, so it does not affect the image license. Not shipped.
- **Last push:** 2026-10-30. **Open issues:** 11. **Recent contributors:** 17 (all-time 66).
- **macOS 27 / Apple silicon:** build host only, inside Lima.
- **Alternatives rejected:** `squashfs-tools` (not chosen, since erofs is read-only and mounts directly). Not recorded elsewhere.
- **Replacement plan / cost:** Low. Only `build.sh` and the initramfs `erofs` module depend on the format.

### Xwayland (guest package, `xwayland`)

- **Used by:** the guest, for X11 apps. The `xwayland` Alpine package is in `image/packages`. It is the X server that xwayland-satellite runs (see its entry below).
- **Version pinned:** not pinned. The upstream X server (`xorg/xserver`) is on freedesktop GitLab. Its metadata was reached through the GitLab API and showed recent activity on 2026-10-31. The Alpine package version was not captured in this audit.
- **License:** MIT (Alpine `community`, aarch64). Compatible.
- **macOS 27 / Apple silicon:** runs in the guest only.
- **Alternatives rejected:** a host-side XQuartz (not chosen; see `docs/research/mac-compositors.md`).
- **Replacement plan / cost:** Done: xwayland-satellite now runs the X clients (below). Xwayland remains a runtime dependency of satellite.

### xwayland-satellite (Rust, `xwayland-satellite`, built from source)

- **Used by:** the guest, as `/usr/bin/xwayland-satellite`. `crosswindd` supervises it on display `:0` against the compositor socket (`guest/crosswindd/src/satellite.rs`). Built by `image/build-xwayland-satellite.sh` (`make guest`) and installed by `image/build.sh` when `XWAYLAND_SATELLITE` is set.
- **Version pinned:** tag **v0.8.3** (`XWS_TAG` in `image/build-xwayland-satellite.sh`), built with `cargo build --release --locked`. Released 2026-09-24 (GitHub latest).
- **License:** MPL-2.0 (`Cargo.toml` and GitHub). Compatible with AGPL-3.0-or-later as a Larger Work (MPL-2.0 Section 3.3 lists AGPL-3.0 as a Secondary License). MPL-2.0 is file-level copyleft: changes to its files must stay MPL.
- **Runtime libraries:** `xwayland` and `xcb-util-cursor` (`image/packages`). Build packages: `libxcb-dev`, `xcb-util-cursor-dev`, `pkgconf`, `git`, `cargo`.
- **Compositor requirements:** xdg_shell and wp_viewporter (both implemented). Optional: fractional scale, which crosswindd advertises.
- **macOS 27 / Apple silicon:** the guest is aarch64 Linux. Not relevant to the macOS side.
- **Not packaged** in Alpine 3.23 or edge (`apk search xwayland-satellite` is empty), hence the source build.
- **Alternatives rejected:** in-process X11 window manager (`X11Wm` in Smithay), kept as a fallback only if clipboard or drag-and-drop control needs it (`docs/research/guest-integration.md`).
- **Replacement plan / cost:** Bump `XWS_TAG` deliberately and re-verify. Fractional-scale rounding in xwayland-satellite needs a host-side workaround (`docs/research/integration-areas.md`).


## Guest image packages (`image/packages`)

License column is the Alpine v3.23 package license (`pkgs.alpinelinux.org/package/v3.23/<repo>/aarch64/<name>`). Repo column is `main` or `community`.

| Package | Repo | License | Note |
|---|---|---|---|
| alpine-baselayout | main | GPL-2.0-only | Base filesystem layout |
| alpine-conf | main | MIT | Alpine setup scripts |
| busybox | main | GPL-2.0-only | Core utilities |
| busybox-openrc | main | GPL-2.0-only | OpenRC integration |
| openrc | main | BSD-2-Clause | Init system |
| linux-virt | main | GPL-2.0-only | Guest kernel (ships as `Image`) |
| mkinitfs | main | GPL-2.0-only | Initramfs builder |
| e2fsprogs | main | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT | Ext tools |
| iproute2 | main | GPL-2.0-or-later | Networking |
| ca-certificates | main | MPL-2.0 AND MIT | Trust store |
| dbus | main | AFL-2.1 OR GPL-2.0-or-later | Message bus |
| dbus-openrc | main | AFL-2.1 OR GPL-2.0-or-later | OpenRC service |
| flatpak | community | LGPL-2.1-or-later | App sandboxes |
| bubblewrap | main | LGPL-2.1-or-later | Sandbox helper |
| xdg-desktop-portal | community | LGPL-2.1-or-later | Desktop portals |
| xdg-desktop-portal-gtk | community | LGPL-2.1-or-later | Portal backend |
| pipewire | community | LGPL-2.1-or-later | Media server |
| wireplumber | community | LGPL-2.1-or-later | PipeWire session manager |
| pipewire-pulse | community | LGPL-2.1-or-later | PulseAudio compatibility |
| xwayland | community | MIT | X server (see Xwayland entry) |
| mesa-dri-gallium | main | MIT AND SGI-B-2.0 AND BSL-1.0 | GPU drivers |
| mesa-egl | main | MIT AND SGI-B-2.0 AND BSL-1.0 | EGL |
| mesa-gbm | main | MIT AND SGI-B-2.0 AND BSL-1.0 | GBM |
| xkeyboard-config | main | MIT | Keyboard data |
| font-noto | community | OFL-1.1 | Fonts |
| font-noto-emoji | community | OFL-1.1 | Emoji font |
| adwaita-icon-theme | community | LGPL-3.0-or-later OR CC-BY-SA-3.0 | Icons |
| hicolor-icon-theme | main | GPL-2.0-or-later | Icon fallback |
| foot | community | MIT | Terminal (test client) |
| weston-clients | community | MIT | Test Wayland clients |

Not in the guest image: `erofs-utils` (build host only; see above).

## Rejected

Reasons come from `docs/research/source-review.md` unless noted.

- **Cocoa-Way** (`J-x-Z/cocoa-way`, GPL-3.0-only): an application, not a library, at about 60k lines of Rust. Does not use vsock. Study only.
- **waypipe** (upstream, GPL-3.0-or-later): the only candidate with documented `--vsock`, but no macOS support upstream. It would run as an external guest-side binary only, and linking it would pull in GPL. Kept as a possible external-process option.
- **waypipe-darwin** (`J-x-Z/waypipe-darwin`, GPL): a stale fork on 0.11.2 with about 773 `unwrap`/`panic`/`expect` hits and 128 TODO/FIXME. Rebase the 335-line Darwin patch onto upstream instead of depending on the fork.
- **Wawona** (`Wawona/Wawona`): 243k lines across 8+ platforms, 265 `unsafe` lines. Its in-tree iland Mode B documents SIP-off WindowServer code injection. It fetches a runtime catalog from `repo.wawona.io`. It bundles GPL `waypipe` while its own `deny.toml` forbids GPL.
- **vzgpu** (`Quiet-Wolfe/vzgpu`, MIT): an 8.5k-line research prototype. Uses private LaunchServices symbols and has no vsock. Reuse the design, not the code.
- **FreeRDP / Weston RAIL** (Apache-2.0; reason from `docs/research/mac-compositors.md` and `docs/research/transports-ux-tooling.md`, not `source-review.md`): RAIL support in the macOS client was not verified. RDP remoting carries pixels over a different stack than per-surface Wayland forwarding, so it fits the design less well.
