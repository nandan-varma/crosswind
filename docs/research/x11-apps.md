# X11-only Flathub apps for compatibility testing

Checked 2026-10-31 against the Flathub API (`/api/v2/summary/<id>`, `metadata.permissions.sockets` and `arches`).
A candidate has `x11` in its sockets, no `wayland` and no `fallback-x11`, and lists `aarch64`.
These apps are unverified in the guest. The list is for later compatibility testing with xwayland-satellite.

| App id | Name | Sockets | Arches | Notes |
|---|---|---|---|---|
| org.videolan.VLC | VLC | x11, pulseaudio | x86_64, aarch64 | Media player; a useful video and GL test |
| org.audacityteam.Audacity | Audacity | x11, pulseaudio | x86_64, aarch64 | Audio editor |
| org.gnu.emacs | Emacs | x11, pulseaudio | x86_64, aarch64 | Editor; manifest asks for X11 only |
| org.freeciv.Freeciv | Freeciv | x11, pulseaudio | x86_64, aarch64 | Game; no GPU device access in manifest |
| org.jdownloader.JDownloader | JDownloader | x11 | x86_64, aarch64 | Java GUI; proprietary license |
| net.minetest.Minetest | Luanti | x11, pulseaudio | x86_64, aarch64 | Game |

Rejected (they also list `wayland` or `fallback-x11`): Xonotic, OpenTTD, Steam, PPSSPP, mGBA, ScummVM, GIMP, Inkscape, Geany, GnuCash, KCalc, Xournal++, GNOME Mines, Thunderbird (x86_64 only).
