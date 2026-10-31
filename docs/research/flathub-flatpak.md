# Flathub as a catalog for a third-party app store (macOS 27 / Apple silicon host)

Research date: 2026-10-31. All sources were accessed 2026-10-31 unless noted. Several primary pages returned HTTP 404 or lacked the needed detail; those gaps are marked `unknown`.

## Facts

### 1. Flathub API and AppStream metadata

- Flathub API base is `https://flathub.org/api/v2`. Endpoint names (`/appstream/:id`, `/appstreams`, `/summary/:app_id`, `/stats/:app_id`, `/stats`, POST `/search` with `{query, page}`) come from a third-party gist and Apify scraper docs, not official docs. Status: secondary, unverified against the live API.
  - Source: https://gist.github.com/sulincix/7f640e47c537c27605f903353a5a785d (secondary)
  - Source: https://apify.com/kawsar/flathub-apps-scraper/api (secondary)
- Stats: a Flathub issue says `/api/v2/stats` feeds badge download counts and that a downloads-to-installs rename was floated. A scraper reads `installs_total` and `installs_last_month`. Official response schema: `unknown`.
  - Source: https://github.com/flathub-infra/website/issues/31 (secondary, issue text)
  - Source: https://github.com/flathub-infra/website/issues/32 (secondary)
- Official docs say the `/api/v2/docs` page was meant to exist but reportedly never worked in production (2022 issue). Current status: `unknown`.
- Raw daily stats are a JSON feed at `https://flathub.org/stats` (per the same issue). Schema: `unknown`.
- Verification status: Flathub docs describe the process but do not say whether status is exposed via API. A Flathub blog post says over half of apps are verified and that status shows on flathub.org and GNOME Software. API exposure: `unknown`.
  - Source: https://docs.flathub.org/docs/for-app-authors/verification
  - Source: https://docs.flathub.org/blog/app-safety-layered-approach-source-to-user (secondary, via search)
- Verification methods (official): (a) `.well-known` token file on the domain in the app ID (one token per line, HTTPS, redirects followed); (b) TXT record `_flathub.{domain}`; (c) source-host login for `io.github.`, `io.gitlab.`, `org.gnome.`, `org.kde.` IDs. Verification applies to apps only, not extensions or runtimes. New `com.github.`/`com.gitlab.` IDs are not accepted.
  - Source: https://docs.flathub.org/docs/for-app-authors/verification
- AppStream/metainfo quality guidance (official):
  - Screenshots: at least one English screenshot, language-tagged (`xml:lang`), window-only, at most 1000x700 (2000x1400 HiDPI), one-sentence caption with no final period, best first, must match current UI. 3-6 is the suggested range for medium apps.
  - Name: ideally 15 characters or fewer (under 20). Summary: ideally 10-25 characters (no more than 35), non-technical.
  - Brand colors: `light` and `dark` primary colors.
  - Release notes: required per release, must be specific.
  - Age ratings: must account for content reachable through the app, including default sources.
  - Developer: shown via verification.
  - Categories and license: the quality page does not specify rules. Summary must not repeat license text. Field schema: `unknown` from this page.
  - Source: https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines
- Permissions (`finish-args`): official policy says keep static permissions minimal and use XDG portals where a suitable portal exists. Network and other invasive permissions are rejected for end-of-life or high-risk software. Build-time `--share=network` does not work. Field-level detail for `finish-args` is `unknown` from this page.
  - Source: https://docs.flathub.org/docs/for-app-authors/requirements

### 2. Terms, licensing, rate limits, branding for third-party clients

- Flathub terms page (`https://docs.flathub.org/docs/for-users/terms`) returned HTTP 404 on 2026-10-31. Terms of use, trademark/branding rules, third-party-client rules, and rate limits: `unknown`.
- The only license statement found is that the Flathub docs are CC BY 4.0. App licensing is per-app, not set by Flathub.
  - Source: https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines (footer)
- Rate limits: `unknown`.
- Implication: before shipping a third-party client, read the Flathub site terms and the flathub-infra website repo (`github.com/flathub-infra`) and ask Flathub maintainers in writing. Do not assume the API is stable or licensed for redistribution.

### 3. aarch64 coverage

- Flathub builds on both `x86_64` and `aarch64` by default. Apps that support only one architecture must add a `flathub.json` at the manifest root.
  - Source: https://docs.flathub.org/docs/for-app-authors/requirements
- Count of apps with aarch64 builds: `unknown` (no published figure found).
- Download share: a 2025 report says x86_64 was about 98.7% of Flathub downloads (about 432.6M) and aarch64 about 1.3% (about 5.5M). Secondary source.
  - Source: https://linuxiac.com/flathub-sees-over-435-million-downloads-in-2025/ (secondary)
- App totals conflict across sources (about 2,800 at end of 2025 per one article; 3,542 per a 2026 guide). Treat as `unknown`.
  - Source: https://www.fosslinux.com/157752/flathub-flatpak-complete-guide.htm (secondary)
- How to measure aarch64 coverage yourself (official Arm guide):
  - `flatpak remote-ls --app --arch=aarch64 flathub` lists every app with a native aarch64 build. Pipe to `wc -l` for a count.
  - Per-app check: `flatpak info <app-id>` and look for `Arch: aarch64`.
  - Source: https://learn.arm.com/install-guides/flatpak/
- Note: the `remote-ls` output reflects the live remote on the day you run it. Re-run before publishing any number.

### 4. Verifying catalog data and ostree commits

- Flatpak repos are ostree repos. Signing is done with `flatpak build-update-repo --gpg-sign=<KEYID>` (CI command on the Flatpak hosting page). Clients get the public key from a `.flatpakrepo` (`GPGKey=`, base64) or `.flatpakref` file.
  - Source: https://docs.flatpak.org/en/latest/hosting-a-repository.html
  - Source: https://docs.flatpak.org/en/latest/repositories.html
- OSTree summary: the summary file can be GPG-signed as a detached signature. Signing the summary is the only way to GPG-sign static deltas. Fetching the summary over pinned TLS gives end-to-end verification of commits and deltas without GPG. The summary must be regenerated with `ostree summary -u` after each ref change.
  - Source: https://ostreedev.github.io/ostree/repo/
- Commit-signature commands (`ostree --gpg-verify`), `summary.sig` naming, and collection-ID trust model: `unknown` (the OSTree docs fetch did not include them). Check the OSTree man pages (`ostree-pull`, `ostree-remote`) directly.
- Flathub's own repo signing key: `unknown` (not verified against a live `.flatpakrepo`). Pin the key fingerprint yourself by fetching `https://dl.flathub.org/repo/flathub.flatpakrepo` and checking the key against a known fingerprint out-of-band.
- Catalog metadata (AppStream JSON from the API): no signature scheme documented. Treat it as untrusted. Verify installs via the ostree/GPG path, not the API response.

### 5. Flatpak in a headless arm64 VM guest

- Bubblewrap needs unprivileged user namespaces (setuid mode dropped in bubblewrap 0.12.0). Hardened kernels or AppArmor can block them. Check `user.max_user_namespaces` and related sysctls.
  - Source: https://wiki.archlinux.org/title/Bubblewrap
  - Source: https://groups.google.com/g/linux.debian.bugs.dist/c/DI_oZSshMeQ
- Portal components needed in the guest: `xdg-desktop-portal` plus a backend (GTK or GNOME, depending on the desktop), D-Bus session bus, and PipeWire for screen capture and camera. Headless guests usually need the display and session environment imported into the systemd user manager and D-Bus activation environment, or portals will not start.
  - Source: https://wiki.archlinux.org/title/XDG_Desktop_Portal
  - Source: https://github.com/flatpak/xdg-desktop-portal/issues/433 (portal segfault when PipeWire connection fails)
- Headless PipeWire with dbus in a VM: `unknown` (no guide found).
- Multi-arch: Flatpak on aarch64 installs aarch64 runtimes and apps natively. Running x86_64 Flatpak apps on an arm64 host requires an emulator layer. Flatpak has no official, documented x86_64 emulation path (`unknown`).
  - Source: https://learn.arm.com/install-guides/flatpak/
  - Emulator options (Fedora change proposal): QEMU, box64, and FEX run x86_64 user code on aarch64. FEX needs a 4K page-size kernel and its own x86-64 RootFS. box64 cannot run 32-bit x86.
    - Source: https://fedoraproject.org/wiki/Changes/FEX (secondary, via search)
  - Experimental wrapper: `fexwrap` runs x86_64 Flatpaks under FEX without binfmt registration. Self-described as janky.
    - Source: https://codeberg.org/valpackett/fexwrap (secondary, via search)
- Rosetta 2 (Apple) is for Linux guests only if the guest hypervisor exposes it (Virtualization.framework on macOS 27). Whether this works with Flatpak: `unknown`.
- Known issues: portal crashes without PipeWire; portal app identification needs `/.flatpak-info` (a bwrap-nested D-Bus proxy broke this for one user); xdg-desktop-portal tests fail without namespaces.
  - Source: https://github.com/flatpak/xdg-desktop-portal/issues/1076

### 6. Permission overrides (Flatseal-like tooling)

- `flatpak override` sets per-app permissions (user or system scope). Options named in the task (`--filesystem`, `--socket`, `--device`, `--env`, `--unset-env`, `--reset`, `--show`) are the expected surface; the reference page fetch was truncated before the `flatpak-override` section, so exact flags are `unknown` from this research and must be checked with `man flatpak-override`.
  - Source: https://docs.flatpak.org/en/latest/flatpak-command-reference.html (truncated)
- Denying a permission: `--nosocket=NAME`, `--unshare=NAME`, and conditional forms like `--socket-if=x11:!has-wayland` are documented.
  - Source: https://docs.flatpak.org/en/latest/sandbox-permissions.html
- Flatseal is a GUI on top of `flatpak override`. Its exact behavior: `unknown` (not fetched).

### Alternatives (brief)

- Snap: Canonical-controlled store and proxy; not a fit for a third-party catalog without running a store. Rejected: `unknown` (not researched in depth).
- AppImage: no central runtime or ostree signing; per-file verification only. Rejected for catalog use.
- Distro packages (apt/dnf/pacman): per-distro, no single catalog, arm64 coverage varies. Rejected for cross-distro catalog.

## Assumptions

- The Flathub API endpoints listed are current. They come from third-party docs and were not checked against the live API.
- `flatpak remote-ls --arch=aarch64` reflects the live catalog. Its count changes over time.
- The user's guest is a Linux arm64 VM on macOS 27 Apple silicon (Virtualization.framework or similar), not an x86_64 guest.
- A third-party store will mirror Flathub's ostree repo rather than hit Flathub's API at runtime.

## Opinions

- Mirror the ostree repo and verify GPG signatures; do not depend on the unofficial API for install-time trust.
- Treat the Flathub API as an unstable, unlicensed dependency until Flathub confirms terms in writing.
- For x86_64 apps on Apple silicon, prefer showing "no arm64 build" and skipping them over shipping an emulation layer. The FEX/fexwrap path is too experimental for a product.
- Use `flatpak remote-ls --arch=aarch64` in CI to publish a coverage number rather than quoting one from memory.

## Search log

- WebFetch: https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines — got screenshot/name/summary rules; no category or license field rules.
- WebFetch: https://docs.flathub.org/docs/for-users/terms — HTTP 404.
- WebSearch: "Flathub API v2 documentation endpoints appstream summary" — only third-party gist and Apify pages.
- WebFetch: https://docs.flathub.org/docs/for-app-authors/verification — got verification methods; no API status info.
- WebFetch: https://github.com/flathub/flathub/wiki/App-Submission — moved; redirect to docs.flathub.org submission page (not fetched).
- WebFetch: https://docs.flatpak.org/en/latest/repositories.html — got `.flatpakref` GPG info only.
- WebFetch: https://docs.flatpak.org/en/latest/hosting-a-repository.html — got repo signing commands.
- WebFetch: https://docs.flathub.org/docs/for-users/usage — HTTP 404.
- WebSearch: "Flathub aarch64 arm64 apps count percentage x86_64 only" — download share (secondary); no app count.
- WebFetch: https://docs.flathub.org/docs/for-app-authors/requirements — architecture and permissions rules.
- WebFetch: https://learn.arm.com/install-guides/flatpak/ — `remote-ls --arch=aarch64` command.
- WebSearch: "flatpak multiarch x86_64 emulation ..." — FEX/box64/QEMU background; fexwrap.
- WebFetch: https://docs.flatpak.org/en/latest/sandbox-permissions.html — deny/conditional permissions only.
- WebFetch: https://docs.flatpak.org/en/latest/requirements.html — HTTP 404.
- WebSearch: "flatpak headless VM guest xdg-desktop-portal pipewire ..." — portal/PipeWire/userns issues.
- WebFetch: https://docs.flatpak.org/en/latest/flatpak-command-reference.html — truncated before flatpak-override section.
- WebFetch: https://ostreedev.github.io/ostree/repo/ — summary signing only.
- WebSearch: "Flathub API stats popularity endpoint ..." — stats field names (secondary).

Not fetched (time budget): Flathub API source repo (`github.com/flathub-infra/website`), OSTree man pages, Flatseal source, Virtualization.framework Rosetta notes, Snap/AppImage comparisons.

## Measured correction (2026-10-31, by the lead, reproducible)

The earlier "0 aarch64 refs" reading in guest-stack.md is wrong: Flathub's main `summary` holds x86_64 only; per-arch refs live in sub-summaries listed by `summary.idx`.
- `curl https://dl.flathub.org/repo/summary.idx`: GVariant map `arch name -> (32-byte sha256, ...)`; the aarch64 checksum is the 32 bytes after `aarch64\0`.
- `curl https://dl.flathub.org/repo/summaries/<hex>.gz`, then `strings | grep '^app/.*/aarch64/'`.
- Result: **3538 distinct apps with an aarch64 ref vs 4128 with x86_64 (about 86% coverage)** in that snapshot (counts include non-stable branches). Supersedes the "1.3% of downloads" framing for catalog purposes; arm64 coverage is not a blocker.
- Flathub repo GPG key fingerprint (from guest-stack agent): 6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE (to be re-verified against the .flatpakrepo key in Phase 1).
