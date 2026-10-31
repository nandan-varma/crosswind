# Guest integration building blocks (research)

Date of research: 2026-10-31. Scope: Rust guest daemon on Alpine aarch64, Smithay-based compositor, mirroring windows to a macOS host over vsock.

Structure: Facts (with URL and date), Assumptions, Opinions, Search log. Items not verified are marked UNKNOWN.

---

## 1. Smithay protocols and Xwayland

### Facts

- Smithay repo: https://github.com/Smithay/smithay. `gh api` on 2026-10-31: license MIT, pushed 2026-10-29T15:51:23Z, latest release v0.7.0 (2025-06-24). Cargo.toml version 0.7.0, `wayland-protocols` 0.32.13 (features unstable, staging, server), `wayland-protocols-misc` 0.3.12, `wayland-server` 0.31.13.
- Checked out shallow at `/tmp/cw-ref2`, HEAD `f581531` ("gles: fix y-inverted texture matrix missing translation"), committer date 2026-10-29. Source grep of `src/wayland/` (checked 2026-10-31):

| Protocol | Smithay module (path under `src/wayland/`) | Present |
|---|---|---|
| text-input-v3 | `text_input/` (`ZwpTextInputV3`, `ContentHint`, `ContentPurpose`) | yes |
| input-method (v2, zwp) | `input_method/` (`zwp_input_method_v2`, `zwp_input_method_manager_v2` from wayland-protocols-misc), includes `input_method_popup_surface.rs`, `input_method_keyboard_grab.rs` | yes |
| primary-selection | `selection/primary_selection/` | yes |
| wlr-data-control | `selection/wlr_data_control/` | yes |
| ext-data-control | `selection/ext_data_control/` | yes (not requested, bonus) |
| cursor-shape-v1 | `cursor_shape.rs` | yes |
| xdg-activation | `xdg_activation/` | yes |
| xdg-toplevel-icon | `xdg_toplevel_icon.rs` (`XdgToplevelIconManager`, `XdgToplevelIconHandler`) | yes |
| idle-inhibit | `idle_inhibit/` | yes |
| pointer-constraints | `pointer_constraints.rs` | yes |
| relative-pointer | `relative_pointer.rs` | yes |
| presentation-time | `presentation/` | yes |
| single-pixel-buffer | `single_pixel_buffer/` | yes |
| xdg-foreign | `xdg_foreign/` | yes |
| session-lock (ext-session-lock) | `session_lock/` (`lock.rs`, `surface.rs`) | yes, despite the request's "session-lock no" note. Treat as available if needed. |

Other present modules that matter here: `xdg_dialog`, `xdg_system_bell.rs`, `xdg_toplevel_tag.rs`, `fractional_scale/`, `viewporter/`, `keyboard_shortcuts_inhibit/`, `pointer_warp.rs`, `image_copy_capture/`, `security_context/`, `foreign_toplevel_list/`.

- Clipboard/DnD: `src/wayland/selection/mod.rs` defines `pub trait SelectionHandler` with `type SelectionUserData`. Data-device DnD goes through `DndGrabHandler` / `WaylandDndGrabHandler` (`selection/data_device/`).
- Xwayland: Cargo feature `xwayland = ["encoding_rs", "wayland_frontend", "x11rb/composite", "x11rb/xfixes", "x11rb/randr", "x11rb_event_source", "scopeguard"]` (Cargo.toml line 117). The feature is in `default`. Modules: `src/xwayland/mod.rs`, `x11_sockets.rs`, `xserver.rs`, `xwm/`, `xwayland_keyboard_grab.rs` and `src/wayland/xwayland_shell.rs`.
- `X11Wm` is `pub struct X11Wm` in `src/xwayland/xwm/mod.rs`. Public methods include `new_selection(...)` and `send_selection(...)`.
- `XwmHandler` (`src/xwayland/xwm/mod.rs`, trait at line 359) has selection hooks, verified in source:
  - `allow_selection_access(&mut self, xwm, selection) -> bool`
  - `send_selection(&mut self, xwm, selection, mime_type: String, fd: OwnedFd)`. Default panics if access was allowed without an implementation.
  - `new_selection(&mut self, xwm, selection, mime_types: Vec<String>)`
- The XWM code handles Xdnd atoms (`XdndSelection`, `XdndEnter`, `XdndPosition`, `XdndDrop`, etc.) and has `mod dnd;` with `XwmOfferData`. So X11 clipboard and DnD bridging to Wayland selections is implemented in-process, not via a separate tool.
- xwayland-satellite: https://github.com/Supreeeme/xwayland-satellite. `gh api` on 2026-10-31: license MPL-2.0, pushed 2026-10-28T12:59:52Z, latest release v0.8.3 (2026-09-24).

### Assumptions

- xwayland-satellite runs as a separate process and presents X11 windows as ordinary Wayland toplevels to the compositor. The compositor then needs no X11 code at all. (Based on the project's documented design; not re-verified in the README this session.)
- Smithay's in-tree `X11Wm` is the path used by Smithay's own anvil/niri-style compositors, so it is maintained but needs compositor-side integration per window.

### Opinion (Xwayland)

Recommend **xwayland-satellite as a separate process**. Reasons:
1. It keeps X11 window management (ICCCM/EWMH quirks, override-redirect, stacking, XWM selection) out of the daemon. Our daemon would otherwise own a second window model.
2. It is maintained upstream (last push 2026-10-28, release 2026-09-24) and tested against many X apps.
3. MPL-2.0 is file-level copyleft. Running it as an unmodified separate binary imposes no obligations on our code. Keep it unmodified, or ship its source for modified files.
4. The cost is an extra process and a copy of the window contents, which is acceptable for a guest mirror.

Use `X11Wm` only if we later need tight clipboard/DnD control between X and Wayland that satellite cannot give. That would be the one reason to take on the in-process code.

### API sketch (protocols)

```rust
// Smithay 0.7 style. Each global is created with its state struct and a handler trait.
use smithay::wayland::selection::primary_selection::PrimarySelectionState;
use smithay::wayland::selection::wlr_data_control::DataControlState;
use smithay::wayland::xdg_toplevel_icon::XdgToplevelIconManager;
use smithay::wayland::idle_inhibit::IdleInhibitManagerState;
use smithay::wayland::pointer_constraints::PointerConstraintsState;
use smithay::wayland::relative_pointer::RelativePointerManagerState;
use smithay::wayland::presentation::PresentationState;
use smithay::wayland::xdg_activation::XdgActivationState;
use smithay::wayland::text_input::TextInputManagerState;
use smithay::wayland::input_method::InputMethodManagerState;
// Exact constructor signatures (new(&DisplayHandle, ...)) and handler traits must be
// read from src/wayland/<module>/mod.rs in the checkout before coding. Not compiled here.
```

UNKNOWN: whether each module's constructor argument lists are exactly as shown above. Only presence and file layout were verified.

---

## 2. xdg-desktop-portal backends (Rust)

### Facts

- Interface files in the upstream repo (`flatpak/xdg-desktop-portal`, `data/`, pushed 2026-10-30T00:24:54Z, fetched 2026-10-31) include `org.freedesktop.impl.portal.*` XML for: Access, Account, AppChooser, Background, Clipboard, DynamicLauncher, Email, FileChooser, GlobalShortcuts, Inhibit, InputCapture, Lockdown, Notification, PermissionStore, Print, RemoteDesktop, Request, ScreenCast, Screenshot, Secret, Session, Settings, Usb, Wallpaper.
- The frontend-only interfaces (`org.freedesktop.portal.*`) include OpenURI, Notification, FileChooser, Settings, etc. No `org.freedesktop.impl.portal.OpenURI.xml` exists in that list. So **OpenURI has no backend interface in the upstream set**; the frontend handles it (see Assumptions).
- Existing Rust backends:
  - `pop-os/xdg-desktop-portal-cosmic`: GPL-3.0, pushed 2026-10-20T21:53:28Z, Cargo `version = "1.11.0"`, uses `zbus = "5.15.0"` (default-features off, `tokio`). Ships `cosmic.portal` and `cosmic-portals.conf`, and a `data/` set of XML and `dbus-1` service files.
  - `emersion/xdg-desktop-portal-wlr`: MIT, pushed 2026-10-29T17:53:21Z (C).
  - `flatpak/xdg-desktop-portal-gtk`: LGPL-2.1, pushed 2026-09-29 (C).
  - `hyprwm/xdg-desktop-portal-hyprland`: BSD-3-Clause, pushed 2026-10-28 (C++).
  - Community Rust examples found via `gh search repos`, not inspected in depth: `olibrks/ttypicker` (MIT, pushed 2026-10-03, FileChooser via terminal); `houdert6/xdg-desktop-portal-nvim` (GPL-3.0, WIP); `LeReverandNox/xdg-desktop-portal-niri` (GPL-3.0, ScreenCast).
- Repos not found via gh (404, names wrong): lxqt-wayland, aidanhs/termfilechooser (the working one is `Osso/xdg-desktop-portal-termfilechooser`, license blank), luminous, and `ksni/ksni` (the working repo is `iovxw/ksni`, Unlicense, pushed 2026-10-20).
- zbus: https://github.com/z-galaxy/zbus. `gh api` on 2026-10-31: pushed 2026-10-31T13:33:07Z, latest release `zbus-6.2.0` (2026-10-29T20:57:30Z). Workspace Cargo.toml: `license = "MIT"`, `rust-version = "1.89"`. GitHub reports NOASSERTION, which is a detection artifact of the multi-file license layout. Also cosmic pins zbus 5.15, so an app can choose either major version.

### Assumptions

- Flatpak apps call `org.freedesktop.portal.*` on the session bus. The frontend (`xdg-desktop-portal`) selects a backend from `portals.conf` and forwards to `org.freedesktop.impl.portal.*` on the same bus, using the `.portal` file to bind the name.
- The `.portal` file goes into `/usr/share/xdg-desktop-portal/portals/`. The format is `[portal]` with `DBusName=org.freedesktop.impl.portal.desktop.<name>`, `Interfaces=...`, `UseIn=...`. Verified only indirectly via cosmic's `cosmic.portal` file name; exact fields not re-read.
- OpenURI: the frontend launches the URI handler itself (via GIO/GAppInfo on the guest). Therefore the "open in macOS browser" path needs a guest `xdg-open`/GIO handler shim, not an OpenURI impl. UNKNOWN until checked against the frontend source.

### Minimal set for "native" Flatpak behavior

Implement these `org.freedesktop.impl.portal.*` interfaces in the daemon (or a small companion service) and forward each to macOS over vsock:

1. **Settings** (`org.freedesktop.impl.portal.Settings`): `Read`/`ReadAll` for `org.freedesktop.appearance` keys `color-scheme` and `accent-color`, plus `SettingChanged` signal when the macOS appearance changes. This gives dark mode and accent color to GTK/Qt apps.
2. **FileChooser** (`org.freedesktop.impl.portal.FileChooser`): `OpenFile`, `SaveFile`, `SaveFiles`. Map to `NSOpenPanel`/`NSSavePanel` on the host. Files must be copied or exposed through the document portal (`org.freedesktop.portal.Documents`) to the sandbox. This is the hardest part.
3. **Notification** (`org.freedesktop.impl.portal.Notification`): `AddNotification`, `RemoveNotification`, `ActionInvoked` signal. Map to `UNUserNotificationCenter` on the host.
4. **Inhibit** (`org.freedesktop.impl.portal.Inhibit`), optional but cheap: `Inhibit`, `CreateMonitor`. Map to `IOPMAssertion` on the host.
5. **Screenshot** and **Account** are not needed for the stated goal and should be deferred.

Frontend side: `xdg-desktop-portal` must be installed in the guest. `portals.conf` routes each interface to our backend, e.g. `[preferred] default=gtk` and `org.freedesktop.impl.portal.FileChooser=ours`.

### API sketch (zbus, backend side)

```rust
// zbus 6.x (MIT). Interface name and method per the upstream XML.
use zbus::{interface, zvariant::{OwnedValue, Value}, Connection};
use std::collections::HashMap;

struct Settings;

#[interface(name = "org.freedesktop.impl.portal.Settings")]
impl Settings {
    async fn read(&self, namespace: &str, key: &str) -> zbus::fdo::Result<OwnedValue> {
        // map to host NSApp.effectiveAppearance / accent color over vsock
        todo!()
    }
    async fn read_all(&self, namespaces: Vec<&str>) -> zbus::fdo::Result<HashMap<String, HashMap<String, OwnedValue>>> {
        todo!()
    }
    // #[zbus(signal)] setting_changed(...) emitted on host appearance change
}

// Connection::session().await?.object_server().at("/org/freedesktop/portal/desktop", Settings).await?;
// request_name("org.freedesktop.impl.portal.desktop.crosswind")
```

UNKNOWN: exact method argument types for Settings.Read (`ss` vs `(ss)` variant wrapping) and the required `Request` object pattern for FileChooser. Check against `org.freedesktop.impl.portal.Settings.xml` and `Request.xml` in the upstream repo before coding.

---

## 3. Audio: guest PipeWire to host CoreAudio

### Facts

- Virtualization.framework exposes `VZVirtioSoundDeviceConfiguration` with output and input stream configurations. Input stream: `VZVirtioSoundDeviceInputStreamConfiguration`. Source: https://developer.apple.com/documentation/virtualization/vzvirtiosounddeviceinputstreamconfiguration (fetched via search index, 2026-10-31).
- Apple's Audio docs say an app that configures an audio input device needs `NSMicrophoneUsageDescription`. Without it, the system denies microphone access. Source: https://developer.apple.com/documentation/virtualization/audio (indexed via search, 2026-10-31).
- `source` on an input stream defaults to nil and produces silence. A `VZHostAudioInputStreamSource` routes the host default input device into the guest. Source: developer.apple.com `vzvirtiosounddeviceinputstreamconfiguration` (search index, 2026-10-31).
- A Go binding PR, https://github.com/Code-Hex/vz/pull/282 (dated 2026-10-27), adds an input stream with no host source so the guest gets silence. Shows the silent-input path is a known pattern.
- A VirelaiOS PR (https://github.com/drawmeanelephant/VirelaiOS/pull/2516) reports audio authorization `notDetermined` at attach and boot, with consent deferred to capture start. Single report, untested by us.
- Alpine kernel config `CONFIG_SND_VIRTIO`: **UNKNOWN**. Fetches of `main/linux-virt/config-virt.aarch64` and `main/linux-lts/config-lts.aarch64` from gitlab.alpinelinux.org failed (curl exit 56) on 2026-10-31. The request's premise (`CONFIG_SND_VIRTIO=m`) is not verified.
- Alpine `pipewire` package: the pkgs.alpinelinux.org search page returned no clear version; UNKNOWN.

### Assumptions

- Guest PipeWire can drive an ALSA device created by the `virtio_snd` driver, via its ALSA backend. Standard behavior, not verified on our image.
- VZ virtio-snd output works on Linux guests with the virtio_snd driver. Not verified on this project.

### Options

- A. **virtio-snd (Virtualization.framework)**: no custom protocol. Output works through the framework. Input needs host mic permission and `NSMicrophoneUsageDescription` in the host app, and the consent timing is unclear. Guest needs the virtio_snd kernel module (UNKNOWN in our kernel config).
- B. **Custom PipeWire/PulseAudio tunnel over vsock**: full control, works on any host audio backend. Costs: a protocol to design and maintain, latency tuning, and a host-side CoreAudio renderer to write.

### Opinion

Recommend **A (virtio-snd) for output first**. It needs no custom protocol and the framework handles the host device. Defer input. Input needs its own TCC prompt flow, and the consent behavior is UNKNOWN, so do not promise microphone support until a test on macOS 27 confirms the prompt. Keep option B as a fallback if the guest kernel lacks virtio_snd.

Required host entitlements/keys for input (per Apple audio docs as indexed, to be confirmed): `NSMicrophoneUsageDescription` in Info.plist; sandboxed hosts also need `com.apple.security.device.audio-input`. Second item is from general sandbox knowledge, not verified in this session.

---

## 4. Clipboard

### Facts

- `VZSpiceAgentPortAttachment` (macOS 13+): `sharesClipboard` flag and `spiceAgentPortName` property. Source: https://developer.apple.com/documentation/virtualization/vzspiceagentportattachment (indexed 2026-10-31).
- Guest side needs `spice-vdagent`. Alpine package `spice-vdagent` exists, version 0.23.0, license GPL-3.0-or-later (aports APKBUILD fetched 2026-10-31). Default virtio port `/dev/virtio-ports/com.redhat.spice.0` (Ubuntu manpage, https://manpages.ubuntu.com/manpages/mantic/man1/spice-vdagentd.1.html).
- One third-party installer project notes that clipboard sync works reliably on X11 and may be limited on Wayland (https://github.com/ashik-maybe/spice-vdagent-installer). Single source; not verified.
- Smithay `SelectionHandler` (src/wayland/selection/mod.rs) is the hook for guest selection changes. Data-control and primary selection globals exist (see section 1).

### Options

- A. Spice agent: `spice-vdagent` in the guest talks to the host via VZ's SPICE port. Gives text and images, primary and clipboard. Files: not covered by SPICE clipboard in the normal path (UNKNOWN for our setup).
- B. Custom messages in our existing vsock protobuf channel: our daemon reads selections through `SelectionHandler`/data-control, sends MIME types and bytes, and writes the host NSPasteboard.

### Opinion

Recommend **B (custom messages)**. Reasons:
1. Our daemon already owns the Wayland selection state through Smithay. Running `spice-vdagent` would create a second clipboard owner that talks to an X11-centric agent, the exact problem the installer note describes.
2. Custom messages give full MIME control (text/plain, text/html, image/png, `text/uri-list` for files). Files can go through our own transfer path later.
3. SPICE gives text and images only, and its Wayland behavior is UNKNOWN for us.
4. Cost: a protocol message pair per direction and loop prevention (the guest must not echo host changes back).

Choose A only if we need to avoid writing the protocol, and accept the X11-dependence risk.

---

## 5. Notifications, tray icons, URL handlers

### Facts

- Notification portal: section 2. Host mapping `UNUserNotificationCenter` is not verified in this session (UNKNOWN for exact API details).
- StatusNotifierItem: `iovxw/ksni` (https://github.com/iovxw/ksni), Unlicense, pushed 2026-10-20. Rust crate for an app to publish a tray item. It is a **client** of the watcher, not the watcher.
- The StatusNotifierWatcher (`org.kde.StatusNotifierWatcher`) is a separate service. Whether any Rust crate implements it was **not verified** (UNKNOWN). Writing it with zbus is feasible: it is one interface with `RegisterStatusNotifierItem`, `RegisterStatusNotifierHost`, and properties.
- `org.freedesktop.Notifications` (the non-portal notification spec) is what most apps call directly, even without Flatpak. The daemon can implement it on the guest session bus and forward to the host.

### Opinion

- Notifications: implement `org.freedesktop.Notifications` in the guest daemon, forward to macOS. Also the portal Notification backend (section 2) for sandboxed apps. Both should share one forwarder.
- Tray: implement a minimal StatusNotifierWatcher in crosswindd with zbus (MIT). Use ksni only if our own app needs a tray item. Expect GTK/Qt apps to need the watcher; map each item to an `NSStatusItem` on the host.
- URL handler: a guest `xdg-open` shim (or a `.desktop` file with `MimeType=x-scheme-handler/http;x-scheme-handler/https;` pointing at a small binary) that sends the URL over vsock to the host, which calls `NSWorkspace.open`. Preferable to the OpenURI portal because the frontend's OpenURI path launches a local handler, which is the wrong target. Verify against the frontend source before relying on this.

---

## 6. Webcam, Bluetooth, USB (macOS 27 Accessory Access)

### Facts

- Accessory Access: Apple's macOS 27 framework for passing USB devices into VMs through Virtualization. Developers register a listener, the device is attached as `VZUSBPassthroughDevice` to a USB controller, and the user must assign the device. Sources: UTM PR #7877 (https://github.com/utmapp/UTM/pull/7877) and #7789 (https://github.com/utmapp/UTM/pull/7789); UTM docs (https://docs.getutm.app/guest-support/sharing/usb/); WWDC26 session 224 (https://developer.apple.com/videos/play/wwdc2026/224/). Accessed 2026-10-31 via search index.
- Entitlement: `com.apple.developer.accessory-access.usb` (per UTM PR description). Granted by Apple to the developer.
- Beta limit: on macOS 27 Beta 4, the runtime rejects USB passthrough devices with isochronous endpoints: "A USB passthrough device with isochronous endpoints is not supported." Reported in a UTM beta test (search index, 2026-10-31).
- Parallels says its own USB passthrough works independently of Accessory Access (https://www.parallels.com/blogs/macos-27-golden-gate-parallels-desktop/).
- Apple's Accessory Access reference page was not found in the search results. Listener API and error behavior: UNKNOWN.

### Assessment

- Webcams: UVC webcams use isochronous video endpoints in common configurations. Given the Beta 4 rejection, **webcams are likely not supported** through Accessory Access. No evidence found that a webcam works in a macOS 27 guest. UNKNOWN until tested with a real device.
- Bluetooth: no evidence found of a Bluetooth passthrough path in Virtualization.framework for macOS 27. UNKNOWN. Assume unsupported.
- USB HID and bulk devices: plausible (no isochronous endpoints), not verified.

### Opinion

Out of scope for the first milestone. Document webcam and Bluetooth as unsupported until a device test on macOS 27. Keep USB passthrough as a later feature gated on device class.

---

## Recommendations (summary)

| Area | Recommendation | Confidence |
|---|---|---|
| Xwayland | xwayland-satellite, separate process (MPL-2.0) | medium-high |
| Protocols | Smithay 0.7 has all requested modules; use as-is | high (verified in source) |
| Portal backend | zbus 6.x (MIT); implement Settings, FileChooser, Notification first; add Inhibit later | medium |
| OpenURI | Guest xdg-open/MIME shim to host, not an OpenURI impl | low (unverified frontend path) |
| Audio | virtio-snd output first; defer input; custom PipeWire tunnel as fallback | medium |
| Clipboard | Custom vsock messages via Smithay selection handlers, not spice-vdagent | medium-high |
| Notifications | org.freedesktop.Notifications + portal forwarder | medium |
| Tray | Own StatusNotifierWatcher with zbus if needed | low (watcher crate unverified) |
| Webcam/BT | Unsupported until tested; treat as UNKNOWN | high that they are unproven |

---

## Search log

- `gh api repos/Smithay/smithay` and `releases/latest`; `gh api repos/Supreeeme/xwayland-satellite`; `gh api repos/z-galaxy/zbus` (+ Cargo.toml contents); `gh api repos/pop-os/xdg-desktop-portal-cosmic` (+ Cargo.toml, data listing); `gh api repos/flatpak/xdg-desktop-portal/contents/data`; `gh api repos/{emersion/xdg-desktop-portal-wlr, flatpak/xdg-desktop-portal-gtk, hyprwm/xdg-desktop-portal-hyprland, iovxw/ksni}`. Several guessed repo names returned 404 (lxqt, termfilechooser, luminous, ksni/ksni, smol-rs/zbus, mpv-player/xwayland-satellite, spice-space/spice-vdagent).
- `gh search repos "xdg-desktop-portal backend language:Rust"` (2026-10-31).
- `git clone --depth 1 https://github.com/Smithay/smithay /tmp/cw-ref2` plus `grep` over `src/wayland`, `src/xwayland`, `Cargo.toml`.
- WebSearch: VZVirtioSoundDeviceInputStreamConfiguration microphone permission; VZSpiceAgentPortAttachment clipboard spice-vdagent; macOS 27 Accessory Access USB passthrough.
- curl to pkgs.alpinelinux.org (spice-vdagent: found; pipewire: unclear) and gitlab.alpinelinux.org aports APKBUILD (spice-vdagent 0.23.0, GPL-3.0-or-later) and kernel configs (failed, exit 56).
- `gh api repos/Smithay/smithay/commits/f581531` (committer date 2026-10-29).

Not done: direct reading of xdg-desktop-portal frontend source (OpenURI path); Apple reference pages for Accessory Access and VZVirtioSound (only search-index excerpts); device tests (webcam, mic prompt).
