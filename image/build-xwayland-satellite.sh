#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Builds xwayland-satellite (MPL-2.0, https://github.com/Supreeeme/xwayland-satellite) from a pinned tag
# into $OUT (default /tmp/cw-target/xwayland-satellite). Run inside the Alpine build environment (Lima VM).
# The tag is pinned here; bump it deliberately and update docs/dependencies.md.
# Build dependencies (Alpine): git cargo pkgconf libxcb-dev xcb-util-cursor-dev clang-dev.
set -eu

for pkg in git cargo pkg-config; do
    command -v "$pkg" >/dev/null || { echo "missing $pkg (see header)" >&2; exit 1; }
done

XWS_TAG=v0.8.3
OUT=${OUT:-/tmp/cw-target/xwayland-satellite}
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-/tmp/cw-xws}
export CARGO_TARGET_DIR

SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT

git clone --depth 1 --branch "$XWS_TAG" https://github.com/Supreeeme/xwayland-satellite.git "$SRC/xwayland-satellite"
cd "$SRC/xwayland-satellite"
cargo build --release --locked
mkdir -p "$(dirname "$OUT")"
install -m755 "$CARGO_TARGET_DIR/release/xwayland-satellite" "$OUT"
echo "built $OUT ($XWS_TAG)"
