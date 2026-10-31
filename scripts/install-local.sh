#!/bin/sh
# Builds a Developer ID signed Release of Crosswind (not notarized), replaces /Applications/Crosswind.app,
# installs the guest image from ~/.cache/crosswind-img and opens the app.
# usage: scripts/install-local.sh   (run `make image` first if ~/.cache/crosswind-img is empty)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

IMG_CACHE="$HOME/.cache/crosswind-img"
OUT="$ROOT/build/release"
APP="$OUT/export/Crosswind.app"
DEST=/Applications/Crosswind.app

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

[ -f "$IMG_CACHE/SHA256SUMS" ] || die "no guest image in $IMG_CACHE (run 'make image' first)"

step "Building the signed Release (no notarization)"
NOTARIZE=0 sh scripts/release.sh
[ -d "$APP" ] || die "build did not produce $APP"

step "Quitting running Crosswind and CrosswindHost"
if pgrep -x Crosswind >/dev/null 2>&1; then
    osascript -e 'tell application id "dev.crosswind.app" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Crosswind >/dev/null 2>&1 || break; sleep 1; done
fi
sh scripts/dev-agent.sh uninstall
pkill -x CrosswindHost >/dev/null 2>&1 || true

step "Installing $DEST"
rm -rf "$DEST"
ditto "$APP" "$DEST"

step "Installing the guest image"
MANIFEST="$OUT/GuestImage.json"
sh scripts/image-manifest.sh "$IMG_CACHE" "local-$(date +%Y%m%d%H%M%S)" "file://$IMG_CACHE" > "$MANIFEST"
"$DEST/Contents/MacOS/crosswindctl" image install "$MANIFEST"

step "Opening Crosswind"
open "$DEST"
echo "Manual step: the first launch registers the background agent (CrosswindHost). If macOS asks,"
echo "approve it in System Settings > General > Login Items & Extensions."
