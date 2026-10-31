# Guest stack research

Date of research: 2026-10-31. Raw data for Flathub checks lives in /tmp/flathub (not in the repo).

Legend: **Facts** carry a URL and the date observed. **Assumptions** are unverified. **Opinions** are recommendations. **Gaps** are items not yet researched.

## Facts

### Projects (license, activity from GitHub API, observed 2026-10-31)

| Project | URL | License | Last push | Latest release |
|---|---|---|---|---|
| flatpak/xdg-desktop-portal | https://github.com/flatpak/xdg-desktop-portal | none declared (GitHub reports no SPDX) | 2026-10-30 | 1.22.1 (2026-06-17) |
| emersion/xdg-desktop-portal-wlr | https://github.com/emersion/xdg-desktop-portal-wlr | MIT | 2026-10-29 | v0.8.5 (2026-10-29) |
| systemd/mkosi | https://github.com/systemd/mkosi | none declared by GitHub | 2026-10-30 | v27.1 (2026-09-28) |
| go-debos/debos | https://github.com/go-debos/debos | Apache-2.0 | 2026-10-31 | v1.1.7 (2026-02-06) |
| hashicorp/packer | https://github.com/hashicorp/packer | NOASSERTION (BUSL/MPL split, check LICENSE) | 2026-10-30 | v1.16.2 (2026-10-22) |
| nix-community/nixos-generators | https://github.com/nix-community/nixos-generators | MIT | 2026-01-30 | no GitHub release object |
| buildroot/buildroot (mirror) | https://github.com/buildroot/buildroot | GPL-2.0 family ("other" per GitHub) | 2026-10-30 | tags exist; not checked |
| microsoft/wslg | https://github.com/microsoft/wslg | MIT | 2026-07-06 | v1.0.66 (2025-02-26) |
| J-x-Z/cocoa-way | https://github.com/J-x-Z/cocoa-way | GPL-3.0 | 2026-10-21 | v2.1.2 (2026-10-21) |
| J-x-Z/waypipe-darwin | https://github.com/J-x-Z/waypipe-darwin | GPL-3.0 | 2026-10-02 | not checked |
| neonkore/waypipe | https://github.com/neonkore/waypipe | "other" | 2023-02-22 | stale mirror |
| PipeWire/pipewire | https://github.com/PipeWire/pipewire | NOASSERTION (LGPL/MIT mix) | 2026-10-30 | not checked |

Upstream waypipe is hosted on GitLab (freedesktop), not GitHub. I did not query it; its license is recorded as an assumption below.

### Searches that returned no usable project

These queries returned zero GitHub repos: `xdg-desktop-portal-cros`, `xdg-desktop-portal-garcon`, `garcon portal crostini`, `virtio-snd coreaudio`, `vsock pipewire`, `wayland text-input-v3 ime`, `sway-tray statusnotifier bridge`. Guessed slugs for ReimuNotMoe/xdg-desktop-portal-cros, Peter-Hindley/garcon and NixOS/nixos-generators returned 404. Treat these as "not found under these names", not as "does not exist".

### Flathub-related facts (for the Flathub task, same date)

- Flathub API root `https://flathub.org/api/v2` returns HTTP 301. Its `/appstream` list returns 3395 app IDs (`https://flathub.org/api/v2/appstream`, 2026-10-31, 91,786 bytes). An `?arch=aarch64` query returns identical bytes, so the filter is ignored.
- Backend routes (source: https://github.com/flathub-infra/backend, `app/main.py`, pushed 2022-04-25, Apache-2.0): `/update`, `/category/{category}`, `/developer/`, `/developer/{developer}`, `/appstream`, `/appstream/{appid}`, `/search/{userquery}`, `/collection/recently-updated[/{limit}]`, `/picks/{pick}`, `/popular[/{days}]`, `/feed/recently-updated`, `/feed/new`, `/status`, `/stats`, `/stats/{appid}`, `/summary/{appid}`. Verification routes live in `app/verification.py` and login routes in `app/logins.py`.
- Backend `app/summary.py` builds a per-app `arches` list from the OSTree `xa.cache` keys of the flathub remote summary. Its `validate_ref` enforces `x86_64` for display, and the `arches` pass uses `enforce_arch=False`. So an `arches` field exists in the backend's internal summary cache (`summary:{appid}` in Redis). I did not confirm it is exposed through the public `/summary/{appid}` response.
- Public summary `https://dl.flathub.org/repo/summary` (HTTP 200, 12,779,365 bytes, fetched 2026-10-31): 4112 distinct app IDs with `/stable` refs, all `x86_64`. 3395 of 3395 AppStream IDs are present; 0 have an aarch64 ref. `summary-aarch64` returns 404. `summary.idx` (10,001 bytes) contains the string `aarch64` only in subset tags (`floss-aarch64`, `verified-aarch64`, etc.).
- Caveat: parsing was done with `strings` over the GVariant, not a real OSTree decoder. The 0 count is therefore "no aarch64 app refs visible in the public summary", not proof that Flathub has no aarch64 builds. A proper check needs `ostree`/`flatpak` or a GVariant parser on a Linux host.
- Repo key: `https://dl.flathub.org/repo/flathub.flatpakrepo` (HTTP 200, 2026-10-31). Its `GPGKey` decodes to a 4096-bit RSA key, uid "Flathub Repo Signing Key <flathub@flathub.org>". Primary fingerprint: `6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE`. Signing subkey: `54A6 CDDD 8919 FB20 4200 D8AC 562702E9E3ED7EE8`.
- ToS: `https://flathub.org/terms-of-service` returns 307; `https://flathub.org/en/terms-of-service` returns 404. The website repo (https://github.com/flathub-infra/website, Apache-2.0, pushed 2026-10-31) has `frontend/app/[locale]/terms-and-conditions/`. Its text is generic store boilerplate (purchase limits, accuracy disclaimers) and does not mention API rate limits or an API usage policy. No 429 or rate-limit handling was found in the backend.

## Assumptions

- A1. waypipe (upstream, GitLab freedesktop) is MIT-licensed. Not verified in this pass.
- A2. Virtualization.framework on Apple silicon can boot arm64 Linux with EFI, virtio-blk, virtio-net, virtio-fs, virtio-vsock and virtio-gpu. Not verified against Apple docs in this pass.
- A3. Free page reporting and balloon are available in the guest kernel config used by common distro arm64 cloud images. Not verified against config files.
- A4. Asahi-style 16K pages are not required for Virtualization.framework guests; the default arm64 host page size is 16K on Apple silicon and guests may use 4K. Not verified.
- A5. `xdg-desktop-portal-wlr` is not a fit for a non-wlroots compositor, since it depends on wlr screencopy. Reasoned from its README, not checked.

## Opinions

- O1. Build the portal backends in-tree (file chooser, notification, open-uri) rather than adopting an external project; no existing vsock-to-host portal backend was found.
- O2. Use mkosi for image assembly. It is active (push 2026-10-30, release 2026-09-28) and supports arm64 EFI images. Debos (Apache-2.0) is the fallback if a Debian base is preferred.
- O3. Treat waypipe as a reference design for Wayland proxying, not a dependency to fork, since its license and macOS fork (GPL-3.0) impose copyleft obligations on any linked code.
- O4. Avoid GPL-3.0 code (cocoa-way, waypipe-darwin) in any component that ships inside a permissive-licensed product unless the licensing plan accepts it.

## Gaps (not researched in this pass)

- Audio: PipeWire-to-CoreAudio bridging over vsock or virtio-snd; no search results yet beyond the empty query.
- StatusNotifier tray bridging: no candidate found.
- text-input-v3 / IME: no candidate found; compositor support not surveyed.
- Drag-and-drop across waypipe / cross-domain protocol: not surveyed.
- Minimal distros: Alpine, Fedora minimal, Debian, NixOS, Buildroot are listed but image availability for arm64 Virtualization.framework was not verified. Buildroot tags were not checked.
- Virtualization.framework feature list (virtiofs, vsock, balloon, free page reporting): needs Apple developer docs fetch.

## Search log

- `gh api repos/<slug>` and `/releases/latest` for about 25 slugs (2026-10-31). Several guessed slugs returned 404.
- `gh search repos` for: xdg-desktop-portal-cros, xdg-desktop-portal-garcon, garcon portal crostini, waypipe, virtio-snd coreaudio, vsock pipewire, nixos-generators, buildroot, wayland text-input-v3 ime, xdg-desktop-portal-wlr, sway-tray statusnotifier bridge.
- `curl` on flathub.org/api/v2, /api/v2/stats (empty, 307), /api/v2/appstream (with and without `?arch=aarch64`), dl.flathub.org/repo/{summary, summary.idx, summary-aarch64, summary.aarch64, flathub.flatpakrepo}, flathub.org/en/terms-of-service (404), flathub.org/terms-of-service (307).
- Shallow clones (read only, not executed) of flathub-infra/website and flathub-infra/backend, grepped for routes, `arch`, `aarch64`, `ratelimit`, `limit`, `terms`.
- Not run: WebSearch and WebFetch on Apple Virtualization.framework, Alpine/Fedora/Debian arm64 cloud images, and PipeWire/waypipe upstream pages. These are the first items to close in the next pass.
