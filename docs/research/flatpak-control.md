# Flatpak control and Flathub catalog: research

Retrieved 2026-10-31 (all probes run that day; times UTC from response headers).
Scope: (1) Rust control of Flatpak from an Alpine aarch64 musl guest, (2) AppStream catalog on a macOS Swift host, (3) popularity and trending endpoints.
Raw probe artifacts are in /tmp/flatpak-research (not in the repo).

## Facts

### 1. Rust bindings

- **libflatpak (crate)**: crates.io API `https://crates.io/api/v1/crates/libflatpak` (2026-10-31). Newest 0.7.0, published 2025-11-24, license MIT, repo `https://gitlab.gnome.org/World/Rust/libflatpak-rs`. Prior: 0.6.0 (2024-08-05), 0.5.0 (2024-02-04). Downloads 47,524.
- Repo: GitLab API `https://gitlab.gnome.org/api/v4/projects/World%2FRust%2Flibflatpak-rs` (2026-10-31) reports `last_activity_at` 2025-10-01T13:12:38Z. Latest commit on main: 2025-10-01 ("ci: Generate rustdoc index page"). Workspace members: `libflatpak`, `libflatpak-sys`. Gir-generated, `generator.py`.
- libflatpak `Cargo.toml` (GitLab raw, 2026-10-31): deps `gio = "0.22"`, `glib = "0.22"`, `libc = "0.2"`, plus `libflatpak-sys` (path). `rust-version = 1.85`. Features default `v1_11_1`. The C library is linked via pkg-config to system libflatpak (`libflatpak-sys`, not inspected in full).
- **flatpak (crate)**: crates.io, newest 0.18.1 published 2022-08-17, MIT, repo `https://github.com/louib/flatpak-rs`, 67,580 downloads. Not updated since 2022.
- **flatpak-rs (crate)**: crates.io, same version/date as `flatpak`, MIT, same repo, 76,281 downloads. Crate contents were not inspected beyond crates.io metadata.
- **Alpine package**: `flatpak-dev` exists for v3.23 aarch64 (Alpine package search `https://pkgs.alpinelinux.org/packages?name=flatpak-dev&branch=v3.23&arch=aarch64`, 2026-10-31). APKINDEX `https://dl-cdn.alpinelinux.org/alpine/v3.23/community/aarch64/APKINDEX.tar.gz` lists:
  - `flatpak` 1.16.6-r0, LGPL-2.1-or-later, depends on `so:libc.musl-aarch64.so.1`, `libgio-2.0`, `libglib-2.0`, `libostree-1`, `libgpgme`, `libcurl`, `libappstream.so.5`, `libxml2`, `libpolkit-agent-1`, `libseccomp`, and others.
  - `flatpak-dev` 1.16.6-r0 (dev files) depends on `flatpak-libs=1.16.6-r0` and pkg-config for `gio-2.0`, `glib-2.0>=2.46`, `ostree-1>=2020.8`, `polkit-agent-1`, `libarchive`, `libcurl`, `libzstd`, `xau`, and others.
  - `flatpak-builder` 1.4.7-r0 also present.
- **Transaction API in libflatpak-rs** (`libflatpak/src/transaction.rs` on main, 94 lines, 2026-10-31): hand-written extension trait with `connect_operation_done` (signal args: operation, commit string, TransactionResult) and `connect_operation_error` (args: operation, glib::Error, details; handler returns bool).
- **Generated transaction methods** (`libflatpak/src/auto/transaction.rs`, same date): `add_install`, `add_install_bundle`, `add_install_flatpakref`, `add_update`, `add_uninstall`, `add_default_dependency_sources`, `add_sideload_repo`, `run`, `operations`, `operation_for_ref`, `current_operation`, `set_no_interaction`, `set_no_pull`, `set_no_deploy`, `set_disable_dependencies`, `set_force_uninstall`, `set_reinstall`, `set_default_arch`, `set_parent_window`; signals `connect_new_operation`, `connect_ready`, `connect_add_new_remote`, `connect_choose_remote_for_ref`, `connect_end_of_lifed`, `connect_webflow_start/done`, `connect_basic_auth_start`, `connect_install_authenticator`.
- **Generated progress** (`libflatpak/src/auto/transaction_progress.rs`): `connect_changed`, `progress`, `status`, `bytes_transferred`, `is_estimating`, `start_time`, `set_update_frequency`.
- **Installation** (`libflatpak/src/auto/installation.rs`): `list_installed_refs`, `list_installed_refs_by_kind`, `list_installed_refs_for_update`, `list_installed_related_refs_sync`, `list_unused_refs`, `list_pinned_refs`, `list_remote_refs_sync`, `list_remote_refs_sync_full`, `fetch_remote_size_sync`, `fetch_remote_metadata_sync`, `fetch_remote_ref_sync`, `installed_ref`, `list_remotes`, `remote_by_name`, `add_remote`, `modify_remote`, `remove_remote`, `update_remote_sync`, `launch`, `current_installed_app`, `load_app_overrides`, `cleanup_local_refs_sync`, `prune_local_repo`, `drop_caches`, `is_user`, `storage_type`, `min_free_space_bytes`. Constructors: `new_system`, `new_system_with_id`, `new_user`, `for_path`.
- **InstalledRef** (`auto/installed_ref.rs`): `load_metadata`, `load_appdata`, `appdata_name/summary/version/license/content_rating_type`, `deploy_dir`, `installed_size`, `latest_commit`, `origin`, `subpaths`, `is_current`, `eol`, `eol_rebase`.
- **Instance** (`auto/instance.rs`): `all` (static listing), `app`, `arch`, `branch`, `child_pid`, `commit`, `id`, `info`, `is_running`, `pid`, `runtime`, `runtime_commit`.
- **Remote** (`auto/remote.rs`): `name`, `type_`, `new`, `build`, `builder`, `from_file`.
- **CLI `flatpak list` man page** (`https://raw.githubusercontent.com/flatpak/flatpak/main/doc/flatpak-list.xml`, 2026-10-31): documents `--columns=FIELD,…` and `--columns=all`.
- **`--columns` appears in these man pages**: `flatpak-list` (6 matches), `flatpak-remote-ls` (5), `flatpak-ps` (5), `flatpak-remotes` (5), `flatpak-history` (4). Not present in `flatpak-install`, `flatpak-update`, `flatpak-uninstall`, `flatpak-info`, `flatpak-remote-info`, `flatpak-override`.
- **`--ostree-verbose`** appears in `flatpak-install.xml`, `flatpak-remote-info.xml`, `flatpak-run.xml` (and others) on the flatpak main branch, 2026-10-31.
- **Non-interactive flag name**: `flatpak-install.xml` contains `noninteractive`. The `--no-interaction` spelling was not found in the man pages checked (install/update/uninstall/remote-info). The correct CLI option is `--noninteractive` per these pages.
- **`flatpak override` options** (`flatpak-override.xml`): `env`, `file`, `filesystem`, `own-name`, `reset`, `show`, `talk-name`.
- **`flatpak remote-info`** options include `--show-metadata`, `--show-commit`, `--show-parent`, `--show-ref`, `--supported-arches`, `--cached`, `--arch`, `--app`, `--runtime`, `--system`, `--user`, `--installation`, `--log`, `--verbose`, `--ostree-verbose`.

### 2. AppStream and Flathub catalog

- `https://dl.flathub.org/repo/appstream/x86_64/appstream.xml.gz`: HTTP 200, `content-type: application/octet-stream`, last-modified `Sat, 31 Oct 2026 21:08:07 GMT`, size 10,905,930 bytes gzip, uncompressed about 51.2 MB (gzip ISIZE 51,230,279). Count of `<component ` elements: 4,828.
- `https://dl.flathub.org/repo/appstream/aarch64/appstream.xml.gz`: HTTP 200, last-modified `Mon, 26 Oct 2026 11:10:37 GMT`, size 10,182,981 bytes. Count of `<component `: 4,242.
- `https://dl.flathub.org/repo/appstream/x86_64/appstream-compose.xml.gz`: HTTP 404.
- `https://dl.flathub.org/repo/appstream/x86_64/appstream.xml.gz.asc` and `.sig`: HTTP 404.
- `https://dl.flathub.org/repo/summary.sig`: HTTP 200 (size 0 on HEAD; not downloaded). `https://dl.flathub.org/repo/summary`: HTTP 200 (size 0 on HEAD; not downloaded).
- `https://dl.flathub.org/repo/` directory listing: HTTP 403.
- The ostree `appstream2` branch was not probed directly. The GitHub repo `https://github.com/flathub/flathub` returned HTTP 200.
- **Sample fetched**: `https://flathub.org/api/v2/appstream/org.gnome.Calculator` (HTTP 200, `application/json`). Saved in /tmp/flatpak-research/calc.json. Also the XML component for `ai.jan.Jan` extracted from the x86_64 appstream.xml.gz (saved in /tmp, not the repo).
- **Fields observed in the XML component** (`ai.jan.Jan`, 2026-10-31): `<id>`, `<name>`, `<summary>` (with `xml:lang` variants), `<project_license>`, `<description>` (HTML-like `<p>`, `<ul>`, `<li>`, with `xml:lang`), `<developer>` with `<name>`, `<developer_name>`, `<launchable type="desktop-id">`, `<icon type="cached" width height scale>`.
- **Tag frequencies in the full XML** (`grep -o '<[a-z-]*' | sort | uniq -c`): `<screenshot>` 11,053 occurrences (`<image>` 48,694; `<caption>` 40,396); `<category>` 7,136; `<release>` 14,810; `<bundle>` 4,830; `<custom>` 4,147; `<launchable>` 3,405; `<provides>` 1,942; `<branding>` 1,304; `<control>` 3,172; `<color>` 2,598; `<display>` 789; `<binary>` 1,047; `<keyword>` 87,157.
- **JSON API fields for org.gnome.Calculator** (`/api/v2/appstream/{id}`, 2026-10-31). Top-level keys: `branding`, `bundle`, `categories`, `content_rating_details`, `description`, `developer_name`, `icon`, `icons`, `id`, `isMobileFriendly`, `is_eol`, `is_free_license`, `keywords`, `kudos`, `launchable`, `metadata`, `mimetypes`, `name`, `project_license`, `provides`, `recommends`, `releases`, `requires`, `screenshots`, `summary`, `supports`, `translation`, `type`, `urls`.
  - `name` "Calculator"; `summary` "Perform arithmetic, scientific or financial calculations"; `project_license` "GPL-3.0-or-later"; `developer_name` "The GNOME Project"; `categories` ["Utility","Calculator"]; `keywords` ["arithmetic","scientific","financial"].
  - `screenshots[]`: `caption`, `default`, `sizes[]` with `src`, `width`, `height`, `scale` (e.g. `image-1_orig.png` 410x666, and `image-1_224x363@1.png`).
  - `icons[]`: objects with `type` ("remote") and `url` at several sizes (128x128 example).
  - `releases[]`: `version`, `type`, `timestamp`, `date_eol`, `url`, `description` (HTML `<ul>`), `urgency`, `date`.
  - `content_rating_details`: keyed by locale (`en_US`), with `contentRatingSystem` "ESRB", `minimumAge` 3, and per-category `level` (e.g. `social`, `violence`).
  - `metadata`: `flathub::verification::verified` true, `flathub::verification::method` "website", `flathub::verification::website` "gnome.org", `flathub::verification::timestamp`, `flathub::verification::login_name` null, `flathub::verification::login_is_organization` false.
  - `requires`: `[{"value":"360","type":"display_length"}]`. `recommends`: null.
  - `bundle`: `{"type":"flatpak","value":"app/org.gnome.Calculator/x86_64/stable","runtime":"org.gnome.Platform/x86_64/51","sdk":"org.gnome.Sdk/x86_64/51"}`.
  - `urls`: keys `translate`, `faq`, `contact`, `vcs_browser`, `contribute`, `bugtracker`, `help`, `homepage`, `donation`.
  - No `finish-args`/permissions key. `GET .../appstream/org.gnome.Calculator/permissions` returned HTTP 404.
- **Summary API** `https://flathub.org/api/v2/summary/org.gnome.Calculator` (HTTP 200): top-level keys include `download_size` "1955737", `installed_size` "5081088", `branch` "stable", `arches` ["x86_64","aarch64"], `timestamp`, `branches` (per-branch sizes), and `metadata`. `metadata` is a dict containing `sdk`, `runtime`, `runtimeInstalledSize` 1126776832, `command` "gnome-calculator", `runtimeIsEol`, `extensions`, and **`permissions`**: `{"shared":["ipc","network"],"devices":["dri"],"sockets":["fallback-x11","wayland"],"filesystems":null,"session-bus":null}`.
- **Verification and runtime fields**: `/api/v2/appstream/{id}` exposes `metadata["flathub::verification::*"]`. `/api/v2/collection/popular` hit objects expose `verification_verified`, `verification_method`, `verification_login_name`, `verification_login_provider`, `verification_login_is_organization`, `verification_website`, `verification_timestamp`, `runtime`, `arches`, `app_id`, `main_categories`, `sub_categories`, `installs_last_month`, `favorites_count`, `trending`, `updated_at`, `added_at`, `is_free_license`, `isMobileFriendly`.
- **Popularity endpoints** (curl, 2026-10-31):
  - `https://flathub.org/api/v2/popular/30`, `/popular/7`, `/trending`: all HTTP 404 with body `{"detail":"Not Found"}`.
  - `https://flathub.org/api/v2/collection/popular`: HTTP 200. Keys: `hits`, `query`, `processingTimeMs`, `hitsPerPage` (250), `page` (1), `totalPages`, `totalHits` (3,364), `facetDistribution`, `facetStats`. Top hits: darktable (installs_last_month 244,938, trending -9.19), Sober (202,248), Firefox (201,051).
  - `https://flathub.org/api/v2/collection/popular?days=30` and `?days=1`: HTTP 200. Same totalHits and same top 3 hits as the default call, so the `days` parameter appears to have no effect (observed in top 3 only).
  - `https://flathub.org/api/v2/collection/trending`: HTTP 200. Same response shape (`hits`, `query`, `processingTimeMs`, `hitsPerPage`, `page`, `totalPages`, `totalHits`, `facetDistribution`, `facetStats`). Top: Kitsune (trending 19.999), Scribe (19.998), PKHeX-Avalonia (19.424).
  - `https://flathub.org/api/v2/collection/recently-updated`: HTTP 200 (keys `hits`, `query`, `processingTimeMs`, `hitsPerPage`, `page`).
  - `https://flathub.org/api/v2/collection/verified`: HTTP 200, totalHits 2,215.
  - `https://flathub.org/api/v2/collection/category/Game`: HTTP 200.
  - `https://flathub.org/api/v2/search`: HTTP 405 on GET (search exists, method mismatch).
  - `https://flathub.org/api/v2/stats`: HTTP 307 (not followed).

## Assumptions

- A1. The libflatpak-rs `connect_new_operation` and progress `connect_changed` bindings are generated and usable (the generated stubs exist), but their runtime behavior and handler argument order were not tested against a running daemon.
- A2. The libflatpak-rs crate builds on Alpine musl aarch64 with `flatpak-dev` and its glib/gio 0.22 pkg-config deps. Only the Alpine package existence and the deps listed in APKINDEX were checked; no build was run.
- A3. The Flathub appstream file has no separate detached signature; integrity must come from the OSTree repo signing (`summary.sig`) or from TLS only. Not verified.
- A4. The CLI `--ostree-verbose` and `--noninteractive` flags work as documented in the man pages on Alpine's flatpak 1.16.6.
- A5. `flatpak override` writes to a per-app keyfile under the installation's `overrides/` directory. Not verified in this session; the libflatpak side only exposes `load_app_overrides`.
- A6. Summary API permissions match the `finish-args` of the app's built metadata (the field name and structure were observed for one app only).
- A7. The Flathub API responses are stable for the guest and host use cases; there is no published SLA.

## Opinions

- O1. For the guest daemon, shelling out to the `flatpak` CLI is the lower-risk MVP. The CLI is the reference implementation, its flags are documented in the same man pages used above, and it avoids pinning a GLib main-loop and gio 0.22 into the daemon.
- O2. Use libflatpak-rs only if you need typed `new-operation` and per-operation progress events without parsing terminal output. The cost is a GLib dependency and a C library that must match the Alpine version.
- O3. Do not depend on the `flatpak` or `flatpak-rs` crates. Both are last released in 2022, and their contents were not audited.
- O4. On the Swift host, parse the appstream file (or per-app JSON) with Foundation `XMLParser` (SAX, streaming, no third-party dependency). Gzip needs a decompression step (see Recommendations). Prefer the JSON API for per-app detail screens and the appstream file for full-catalog search.
- O5. Do the catalog parsing on the host and keep the guest focused on install/run operations. The host is the trust boundary that already has network and Swift tooling.

## Recommendations

### Q1: Guest control (Rust, Alpine musl aarch64)

Recommendation: shell out to the `flatpak` CLI for the MVP, parsing `flatpak list --columns=...`, `flatpak remote-ls --columns=...`, `flatpak ps --columns=...`, and `flatpak remotes --columns=...`, and use `--noninteractive` on install/update/uninstall.

Trade-off, concretely:

| Concern | CLI (recommended) | libflatpak-rs 0.7.0 |
|---|---|---|
| Dependencies | `flatpak` binary from Alpine APK | gio/glib 0.22 crates, `libflatpak-sys`, flatpak-dev pkg-config, GLib main loop |
| Install progress | Text on stderr; parse `\r`-separated lines (A4 untested on non-tty) | `connect_new_operation` and `TransactionProgress::connect_changed` (A1 untested) |
| Listing | `--columns` on list/remote-ls/ps/remotes/history | `Installation::list_installed_refs` returns typed objects |
| Overrides | `flatpak override --show/--filesystem/...` | `load_app_overrides` read-only; writing overrides means editing keyfiles (A5) |
| Running instances | `flatpak ps --columns=...` | `Instance::all`, `is_running`, `pid` |
| Error handling | exit codes + stderr | `connect_operation_error` returns `TransactionErrorDetails` |
| Build risk on musl | none beyond packaging | depends on A2 |

If typed progress is required later, add libflatpak-rs behind a cargo feature and keep the CLI path as fallback.

### Q2: AppStream catalog and host Swift

- Use `https://dl.flathub.org/repo/appstream/aarch64/appstream.xml.gz` (4,242 components) or `x86_64` (4,828) depending on which architecture the catalog should advertise. Both exist.
- Download the gz (about 10 MB), decompress, and parse with Foundation `XMLParser` on the host. Stream with a SAX parser rather than building a DOM (51 MB uncompressed). Decompression: Apple's Compression framework exposes raw deflate, so strip the 10-byte gzip header (or shell out to `/usr/bin/gunzip` from a host helper). This is an opinion, not tested.
- Use `https://flathub.org/api/v2/appstream/{id}` for detail views (screenshots, releases, content rating, requires/recommends, verification, URLs, bundle), and `https://flathub.org/api/v2/summary/{id}` for download/installed size and `metadata.permissions`.
- Integrity: verify the OSTree repo signature (`summary.sig` exists; signature-verification procedure not run) before trusting appstream data for anything security-relevant such as permissions. If the appstream file is only fetched over TLS, treat it as untrusted display data.
- Permissions (finish-args) are NOT in appstream. Use the summary API `metadata.permissions` (verified for one app), or `flatpak remote-info --show-metadata <remote> <ref>` on the guest, which reads the commit metadata file.
- Popularity: use `https://flathub.org/api/v2/collection/popular` (hits with `installs_last_month`, `trending`, `favorites_count`, pagination via `page`/`totalPages`) and `https://flathub.org/api/v2/collection/trending`. Do not use `/popular/{days}` or `/trending`, which return 404. The `days` parameter on the collection endpoint appears to be ignored.

## Search log

Commands and URLs run (2026-10-31):

1. `curl https://crates.io/api/v1/crates/{libflatpak,flatpak,flatpak-rs}` -> 200; parsed name, max_version, updated_at, license, repository, versions.
2. `curl -sI https://dl.flathub.org/repo/appstream/x86_64/appstream.xml.gz` -> 200; `.../aarch64/appstream.xml.gz` -> 200; `.../x86_64/appstream-compose.xml.gz` -> 404.
3. `curl https://pkgs.alpinelinux.org/packages?name=flatpak-dev&branch=v3.23&arch=aarch64` -> package page lists flatpak-dev.
4. `curl https://dl-cdn.alpinelinux.org/alpine/v3.23/community/aarch64/APKINDEX.tar.gz` -> extracted; `flatpak` 1.16.6-r0, `flatpak-dev` 1.16.6-r0 parsed.
5. `curl https://flathub.org/api/v2/appstream/org.gnome.Calculator` -> 200 JSON; `/permissions` sub-path -> 404; `/api/v2/summary/org.gnome.Calculator` -> 200.
6. `curl https://flathub.org/api/v2/popular/30`, `/popular/7`, `/trending` -> 404 each.
7. `curl https://flathub.org/api/v2/collection/{popular,trending,recently-updated,verified}` -> 200 each; `?days=1`, `?days=30` -> 200.
8. `curl https://flathub.org/api/v2/collection/category/Game` -> 200; `/api/v2/search` GET -> 405; `/api/v2/stats` -> 307.
9. `gunzip -c appstream.xml.gz | head` and XML tag frequency counts; sample component `ai.jan.Jan` extracted.
10. GitLab API for libflatpak-rs: repo metadata, tree listing, `Cargo.toml`, `libflatpak/src/transaction.rs`, `libflatpak/src/installation.rs`, `libflatpak/src/auto/{transaction,transaction_progress,installation,installed_ref,instance,remote}.rs`.
11. `raw.githubusercontent.com/flatpak/flatpak/main/doc/flatpak-{list,install,update,uninstall,remote-ls,remote-info,ps,override,history,remotes,run}.xml` -> option grep for `--columns`, `--ostree-verbose`, `--noninteractive`, `--show-metadata`.
12. `https://dl.flathub.org/repo/summary.sig` and `/repo/summary` -> 200 (HEAD only); `.asc`/`.sig` for appstream -> 404; `/repo/` listing -> 403.
13. `https://raw.githubusercontent.com/flathub/flathub/master/README.md` -> returned content (Flathub overview). `https://github.com/flathub/flathub` -> 200.

Not done: building libflatpak-rs on musl; running the CLI on Alpine; verifying the summary.sig signature; reading `flatpak` / `flatpak-rs` crate sources; probing `appstream2` ostree branch; Swift parser library evaluation beyond Foundation XMLParser (not benchmarked).
