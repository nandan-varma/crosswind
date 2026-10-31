#!/bin/sh
# Creates or updates appcast.xml for a release DMG with Sparkle's generate_appcast. It signs each enclosure with the
# EdDSA private key that Sparkle's generate_keys stored in the login keychain (the key is never read into this script
# or printed). It publishes nothing: upload the output as a release asset yourself.
#
# usage: scripts/appcast.sh <Crosswind-X.Y.Z.dmg> [previous-appcast.xml]
#   previous-appcast.xml  the appcast of the last published release. Passing it keeps earlier entries; the new
#                         entry is added to it. Without it the appcast lists only this DMG.
# output: build/appcast/appcast.xml
#
# Sparkle's tools are found in SPARKLE_BIN, or in any Xcode DerivedData or -derivedDataPath SourcePackages checkout
# of the Sparkle package (see docs/release.md).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "error: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: scripts/appcast.sh <dmg> [previous-appcast.xml]"
DMG=$1
PREVIOUS=${2:-}
[ -f "$DMG" ] || die "no such file: $DMG"
[ -z "$PREVIOUS" ] || [ -f "$PREVIOUS" ] || die "no such file: $PREVIOUS"

SPARKLE_BIN=${SPARKLE_BIN:-$(find "$HOME/Library/Developer/Xcode/DerivedData" /tmp/dd-compat \
    -type d -path '*/artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -n 1)}
[ -x "$SPARKLE_BIN/generate_appcast" ] || die "generate_appcast not found; set SPARKLE_BIN to Sparkle's bin directory"

VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")
DIR="$ROOT/build/appcast"
rm -rf "$DIR"
mkdir -p "$DIR"
cp "$DMG" "$DIR/"
[ -z "$PREVIOUS" ] || cp "$PREVIOUS" "$DIR/appcast.xml"

# The enclosures are served from the GitHub release tagged v<version>, as documented in docs/release.md.
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/nandan-varma/crosswind/releases/download/v$VERSION/" \
    "$DIR"

[ -f "$DIR/appcast.xml" ] || die "generate_appcast wrote no appcast.xml"
echo "Appcast: $DIR/appcast.xml (not published)"
