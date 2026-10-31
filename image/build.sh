#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Builds the Crosswind guest on Alpine Linux (aarch64) into $OUT:
#   Image        uncompressed arm64 kernel (what Virtualization.framework boots)
#   initramfs    mounts system.erofs read-only under a tmpfs overlay
#   system.erofs the root filesystem
# Run as root on an aarch64 Alpine host (a CI runner or `make image`, which uses a Lima VM).
set -eu

ALPINE_BRANCH=v3.23
OUT=${OUT:-/tmp/crosswind-image}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$OUT"

mkdir -p "$ROOT/etc/apk"
cp -a /etc/apk/keys "$ROOT/etc/apk/keys"
printf '%s\n' "https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/main" \
               "https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/community" > "$ROOT/etc/apk/repositories"
apk --root "$ROOT" --initdb --update-cache --no-cache add $(grep -v '^#' "$HERE/packages" | tr '\n' ' ')

cp -a "$HERE/overlay/." "$ROOT/"
[ -x "${CROSSWINDD:-}" ] && install -Dm755 "$CROSSWINDD" "$ROOT/usr/bin/crosswindd"
# crosswind-open: the URL client that xdg-open execs (built beside crosswindd).
[ -x "${CROSSWINDD:-}" ] && [ -x "${CROSSWINDD%/*}/crosswind-open" ] && install -Dm755 "${CROSSWINDD%/*}/crosswind-open" "$ROOT/usr/bin/crosswind-open"
# xwayland-satellite (built from a pinned tag by image/build-xwayland-satellite.sh); crosswindd runs it as /usr/bin/xwayland-satellite.
[ -x "${XWAYLAND_SATELLITE:-}" ] && install -Dm755 "$XWAYLAND_SATELLITE" "$ROOT/usr/bin/xwayland-satellite"

# Unprivileged account for the daemon (uid 1000). Appended, not overlaid, so the base databases stay intact.
grep -q '^crosswind:' "$ROOT/etc/group" || echo 'crosswind:x:1000:' >> "$ROOT/etc/group"
grep -q '^crosswind:' "$ROOT/etc/passwd" || echo 'crosswind:x:1000:1000:Crosswind:/home/crosswind:/sbin/nologin' >> "$ROOT/etc/passwd"
grep -q '^crosswind:' "$ROOT/etc/shadow" || echo 'crosswind:!:19000:0:99999:7:::' >> "$ROOT/etc/shadow"
# The daemon's audio stack opens /dev/snd, which belongs to group audio (crosswind-data sets the mode at boot).
grep -q '^audio:' "$ROOT/etc/group" || echo 'audio:x:29:' >> "$ROOT/etc/group"
sed -i -e '/^audio:/{/crosswind/!s/:$/:crosswind/;/crosswind/!s/$/,crosswind/;}' "$ROOT/etc/group"

# Every library crosswindd and xwayland-satellite need must be in the image.
for bin in /usr/bin/crosswindd /usr/bin/xwayland-satellite; do
    if [ -x "$ROOT$bin" ] && chroot "$ROOT" ldd "$bin" | grep -q 'not found'; then
        chroot "$ROOT" ldd "$bin" | grep 'not found' >&2
        echo "$bin has unresolved libraries; add their packages to image/packages" >&2
        exit 1
    fi
done

# OpenRC runlevels: only what a headless Wayland host needs.
link() { mkdir -p "$ROOT/etc/runlevels/$1"; ln -sf "/etc/init.d/$2" "$ROOT/etc/runlevels/$1/$2"; }
for s in devfs dmesg; do link sysinit "$s"; done
for s in hostname sysctl modules bootmisc crosswind-data networking; do link boot "$s"; done
for s in dbus crosswindd; do link default "$s"; done
echo crosswind > "$ROOT/etc/hostname"
printf 'auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n' > "$ROOT/etc/network/interfaces"
printf 'virtio_net\nvsock\nvmw_vsock_virtio_transport\nfuse\nvirtiofs\nvirtio_snd\n' > "$ROOT/etc/modules"
: > "$ROOT/etc/fstab"

# Kernel and initramfs. The initramfs uses our own /init (see initramfs-init).
KVER=$(ls "$ROOT/lib/modules")
mkinitfs -b "$ROOT" -P "$ROOT/etc/mkinitfs/features.d" -F "base crosswind" -i "$HERE/initramfs-init" -o "$OUT/initramfs" "$KVER"
python3 - "$ROOT/boot/vmlinuz-virt" "$OUT/Image" <<'PY'
import sys, zlib
d = open(sys.argv[1], 'rb').read()
assert d[4:8] == b'zimg' and d[24:28] == b'gzip'   # EFI zboot wrapper: gzip payload
off = int.from_bytes(d[8:12], 'little'); size = int.from_bytes(d[12:16], 'little')
open(sys.argv[2], 'wb').write(zlib.decompress(d[off:off + size], 31))
PY

rm -rf "$ROOT/boot" "$ROOT/var/cache/apk"
mkfs.erofs -zlz4hc -T0 "$OUT/system.erofs" "$ROOT"
chmod 644 "$OUT"/*
(cd "$OUT" && sha256sum Image initramfs system.erofs > SHA256SUMS)
ls -l "$OUT"
