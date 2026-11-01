# Knowledge base: gotchas, upstream bugs, workarounds

Newest first. Add an entry whenever something cost more than 30 minutes.

- **2026-11-01 document portal needs /dev/fuse for the daemon user:** `xdg-document-portal` (uid 1000, D-Bus activated) mounts FUSE under `$XDG_RUNTIME_DIR/doc`. The devtmpfs node `/dev/fuse` is `0600 root:root`, so the daemon's open fails with EACCES and the mount reports `Can't mount path /run/crosswind/doc`. Fix: `image/overlay/etc/init.d/crosswind-data` loads `fuse` and gives `/dev/fuse` to group `crosswind` (mode 660). Measured in the guest: before, `open /dev/fuse` as uid 1000 = Permission denied; after, Ok, and the portal error is gone from TextEditor/VSCodium logs.
- **2026-11-01 GTK close "does not exit" (TextEditor, Clocks):** three different causes, all measured with the stub's close button (AppKit AXCloseButton) and the stub process as the signal (the stub quits when the guest reports AppExited).
  - TextEditor, unmodified draft: did not close before the FUSE fix (window and stub stayed up); after the fix the window closes and the stub quits (app exits). The Documents-portal calls were stalling the close path.
  - TextEditor, modified document: GTK shows "Save changes?" and keeps the window. This is correct app behaviour. The compat harness types Space and Return before asking for close, so its `cleanExit` fail for TextEditor is this prompt, not a Crosswind bug.
  - Clocks: after the last window closes the process keeps running (GApplication hold; no timer or alarm needed to observe it). The stub stays because the guest app is still running, which is the rule below.
  - Calculator exits on close as expected.
- **2026-11-01 backgrounded-app rule (decided):** an app's stub lives as long as the guest app runs, regardless of window count. When the last window closes, the Dock tile stays only while `AppExited` has not arrived; when the process exits the stub terminates. This is what `App/Stub/main.swift` already does (`watchForExit`), so no code change. Not yet done: reopening a backgrounded app from the Dock (the stub does not handle reopen; a second `flatpak run` would emit an AppExited that terminates the stub, so reopen needs its own design).
- **2026-11-01 idle redraw (measured, not a Crosswind loop):** Calculator, `windows` frame counter sampled each second. Idle after input: 0 frames/s (stable at 603-896 frames across 12 s samples). After one keypress: about 30 frames/s for about 4-5 s, then stop. Per-second guest counters: commits = frames sent = acks = frame callbacks, and no empty-damage renders, so the frame-callback loop does not spin; each frame carries about 16 bytes of LZ4 damage (cursor-sized). The ~7 fps idle figure was not reproduced. The burst is GTK painting for its own animation or caret, paced by the host display-link acks (one per refresh). Not changed.
- **2026-11-01 VSCodium exits 0 right after start:** with the portal fixed, `com.vscodium.codium` prints "Setting up NPM/Cargo/Python packages" and "'ruby' is not available" (from flathub-infra/ide-flatpak-wrapper `vscode.sh`, which ends in `exec` of the editor), then the flatpak process exits with code 0 within about a second. No window, no Electron stderr. Reinstalling the app did not change it. Not diagnosed; the exit code is observed in `crosswindd` (control.rs `Note::Exited`), so the next step is to capture the editor's own stderr or run it with `--verbose`.

- **2026-10-31 macOS key events:** With Cmd held, AppKit does not deliver `keyUp` to the first responder. The per-app stub's `NSApplication.sendEvent` must forward `keyUp` with `.command` to the key window (not yet done; affects Cmd->Ctrl mapping).
- **2026-10-31 guest keyboard focus:** The guest only focuses a window after the host sends `Configure.activated`; headless tests must activate the app (`NSApp.activate()`) or inject focus explicitly.
- **2026-10-31 VZLinuxBootLoader:** rejects EFI zboot kernels (Alpine `vmlinuz-virt`). Extract the gzip payload (see image/build.sh) to get a raw arm64 `Image`.
- **2026-10-31 Flathub aarch64 refs:** not in the main `summary`; use `summary.idx` -> per-arch sub-summary (docs/research/flathub-flatpak.md, measured correction).
- **2026-10-31 Lima:** home directory mounts are read-only by default; the builder instance mounts only this repo, writable (`~/.lima/cwbuild/lima.yaml`).
- **2026-10-31 Alpine mkinitfs:** custom feature files must be passed with `-P <featuredir>`; modules in a feature are paths under `kernel/`.

## Compatibility runs (first batch, 2026-10-31)

- Electron (VSCodium, `com.vscodium.codium`): no window in 90 s. Cause of the portal error fixed (FUSE, see 2026-11-01 entries); the app still exits 0 early, see the VSCodium entry above.
- GTK4 TextEditor and Clocks: see the 2026-11-01 close entry (portal stall fixed; unsaved-changes prompt and GApplication hold explain the rest). Calculator closes cleanly.
- Input and frames were observed for Calculator, TextEditor and Clocks. Rendering is CPU-only in the guest (pixman).
