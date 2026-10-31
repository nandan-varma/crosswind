# Knowledge base: gotchas, upstream bugs, workarounds

Newest first. Add an entry whenever something cost more than 30 minutes.

- **2026-10-31 macOS key events:** With Cmd held, AppKit does not deliver `keyUp` to the first responder. The per-app stub's `NSApplication.sendEvent` must forward `keyUp` with `.command` to the key window (not yet done; affects Cmd->Ctrl mapping).
- **2026-10-31 guest keyboard focus:** The guest only focuses a window after the host sends `Configure.activated`; headless tests must activate the app (`NSApp.activate()`) or inject focus explicitly.
- **2026-10-31 VZLinuxBootLoader:** rejects EFI zboot kernels (Alpine `vmlinuz-virt`). Extract the gzip payload (see image/build.sh) to get a raw arm64 `Image`.
- **2026-10-31 Flathub aarch64 refs:** not in the main `summary`; use `summary.idx` -> per-arch sub-summary (docs/research/flathub-flatpak.md, measured correction).
- **2026-10-31 Lima:** home directory mounts are read-only by default; the builder instance mounts only this repo, writable (`~/.lima/cwbuild/lima.yaml`).
- **2026-10-31 Alpine mkinitfs:** custom feature files must be passed with `-P <featuredir>`; modules in a feature are paths under `kernel/`.

## Compatibility runs (first batch, 2026-10-31)

- Electron (VSCodium, `com.vscodium.codium`): no window in 90 s. The guest log shows `Can't get document portal: Can't mount path /run/crosswind/doc`, so the Flatpak document portal is missing or not mounted in the guest. Electron's startup waits on it. Crosswind bug: the guest needs the document portal (or the app must start without it).
- GTK4 TextEditor (`org.gnome.TextEditor`) and Clocks (`org.gnome.clocks`): a close request did not end the process within 10 s, so the agent had to send SIGTERM (exit 143). Calculator closes cleanly. Not yet diagnosed; suspect the close path or the app staying resident after its last window.
- Input and frames were observed for Calculator, TextEditor and Clocks. Rendering is CPU-only in the guest (pixman).
