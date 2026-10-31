#!/bin/sh
# Archives Crosswind with Developer ID signing, exports it, verifies every signed binary,
# then notarizes and staples the app and builds a notarized DMG. Output: build/release/.
# usage: scripts/release.sh            (full release)
#        NOTARIZE=0 scripts/release.sh (signed app only, no notarization, no DMG)
#
# Guest image: set IMAGE_DIR (a directory built by image/build.sh, with SHA256SUMS) and IMAGE_BASE_URL (where
# the files will be served) to embed GuestImage.json in the app. Without both, the app is built with no manifest
# and the store app installs no guest image; the release says so.
#   IMAGE_DIR=~/.cache/crosswind-img IMAGE_BASE_URL=https://example.com/crosswind/image scripts/release.sh
# IMAGE_VERSION overrides the manifest version (default: first 12 hex digits of SHA256 over SHA256SUMS).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

TEAM=72CW7UW6RB
IDENTITY="Developer ID Application: Nandan Varma Pericharla ($TEAM)"
NOTARIZE=${NOTARIZE:-1}
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Crosswind.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Crosswind.app"
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
MANIFEST="$ROOT/build/GuestImage.json"

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

command -v helpers >/dev/null 2>&1 || die "helpers not found (expected ~/.local/bin/helpers)"
command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found (brew install xcodegen)"

# Checks one signed binary: identity, hardened runtime, secure timestamp, no get-task-allow.
check_binary() {
    path=$1
    info=$(codesign -dvv "$path" 2>&1) || die "$path is not signed"
    echo "$info" | grep -qF "Authority=$IDENTITY" || die "$path is not signed with '$IDENTITY'"
    echo "$info" | grep -q 'flags=0x[0-9a-f]*(runtime)' || die "$path has no hardened runtime"
    echo "$info" | grep -q '^Timestamp=' || die "$path has no secure timestamp"
    ents=$(codesign -d --entitlements :- "$path" 2>/dev/null || true)
    if echo "$ents" | grep -q 'get-task-allow'; then die "$path has the get-task-allow entitlement"; fi
    echo "ok  $path"
}

# A stale manifest from an earlier run must not end up in this build.
rm -f "$MANIFEST"
if [ -n "${IMAGE_DIR:-}" ] || [ -n "${IMAGE_BASE_URL:-}" ]; then
    [ -n "${IMAGE_DIR:-}" ] && [ -n "${IMAGE_BASE_URL:-}" ] || die "set both IMAGE_DIR and IMAGE_BASE_URL"
    [ -f "$IMAGE_DIR/SHA256SUMS" ] || die "no SHA256SUMS in $IMAGE_DIR (run make image first)"
    IMAGE_VERSION=${IMAGE_VERSION:-$(shasum -a 256 "$IMAGE_DIR/SHA256SUMS" | cut -c1-12)}
    step "Writing GuestImage.json ($IMAGE_VERSION) for $IMAGE_BASE_URL"
    sh "$ROOT/scripts/image-manifest.sh" "$IMAGE_DIR" "$IMAGE_VERSION" "$IMAGE_BASE_URL" > "$MANIFEST"
else
    step "No IMAGE_DIR/IMAGE_BASE_URL: building without a guest image manifest"
fi

step "Generating Xcode project"
xcodegen generate

step "Archiving Crosswind $VERSION (Release, Developer ID)"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild archive \
    -project Crosswind.xcodeproj \
    -scheme Crosswind \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM" \
    "RELEASE_SIGN=Developer ID Application" \
    ENABLE_HARDENED_RUNTIME=YES \
    "OTHER_CODE_SIGN_FLAGS=--timestamp" \
    ONLY_ACTIVE_ARCH=NO

rm -f "$MANIFEST"

step "Exporting (developer-id)"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$ROOT/ExportOptions.plist"
[ -d "$APP" ] || die "export did not produce $APP"

step "Verifying signatures"
check_binary "$APP"
check_binary "$APP/Contents/Library/Helpers/CrosswindHost.app"
check_binary "$APP/Contents/Library/Helpers/CrosswindHost.app/Contents/MacOS/CrosswindHost"
check_binary "$APP/Contents/Resources/CrosswindAppStub.app"
check_binary "$APP/Contents/MacOS/crosswindctl"
# Sparkle's nested code (XPC services, Autoupdate, Updater.app) must be Developer ID signed with the hardened
# runtime and a timestamp too. Xcode signs these only when the export does; the check fails the release otherwise.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
[ -d "$SPARKLE" ] || die "Sparkle.framework is not embedded in $APP"
check_binary "$SPARKLE/Sparkle"
check_binary "$SPARKLE/Autoupdate"
check_binary "$SPARKLE/Updater.app/Contents/MacOS/Updater"
check_binary "$SPARKLE/XPCServices/Installer.xpc/Contents/MacOS/Installer"
check_binary "$SPARKLE/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
codesign --verify --deep --strict "$APP" || die "deep signature check failed"
codesign --verify --strict "$SPARKLE" || die "Sparkle.framework signature check failed"

step "Checking the guest image manifest"
if [ -f "$APP/Contents/Resources/GuestImage.json" ]; then
    echo "ok  GuestImage.json embedded ($(awk -F'"' '/"version"/ { print $4; exit }' "$APP/Contents/Resources/GuestImage.json"))"
else
    echo "note: no GuestImage.json in the app (built without IMAGE_DIR/IMAGE_BASE_URL)"
fi

step "Verifying entitlements"
host_ents=$(codesign -d --entitlements :- "$APP/Contents/Library/Helpers/CrosswindHost.app" 2>/dev/null || true)
echo "$host_ents" | grep -q 'com.apple.security.virtualization' \
    || die "CrosswindHost lacks com.apple.security.virtualization"
echo "ok  CrosswindHost has com.apple.security.virtualization"

if [ "$NOTARIZE" != 1 ]; then
    step "NOTARIZE=0: skipping notarization and DMG"
    echo "Signed app: $APP"
    exit 0
fi

step "Notarizing and stapling the app"
helpers sign notarize "$APP"

step "Building the DMG"
STAGE="$OUT/dmg-stage"
DMG="$OUT/Crosswind-$VERSION.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Crosswind.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -format UDZO -volname Crosswind -srcfolder "$STAGE" -ov "$DMG"
rm -rf "$STAGE"

step "Notarizing and stapling the DMG"
helpers sign notarize "$DMG"

step "Verifying the release"
helpers sign verify "$DMG"
echo "Release: $DMG"
