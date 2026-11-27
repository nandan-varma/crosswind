#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Runs crosswindctl from a project-local build (build/dd), building it first when missing, so a cleaned DerivedData
# does not break the development loop. Usage: scripts/ctl.sh <crosswindctl arguments>
#   scripts/ctl.sh --rebuild   rebuild the products and re-register the host agent
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DD=${DERIVED_DATA:-$ROOT/build/dd}
PRODUCTS=$DD/Build/Products/Debug

build() {
    [ -d "$ROOT/Crosswind.xcodeproj" ] || (cd "$ROOT" && make project >/dev/null)
    xcodebuild -project "$ROOT/Crosswind.xcodeproj" -scheme Crosswind -configuration Debug \
        -derivedDataPath "$DD" -quiet build >&2
}

if [ "${1:-}" = "--rebuild" ]; then
    build
    DERIVED_DATA=$DD sh "$ROOT/scripts/dev-agent.sh" install >&2
    exit 0
fi
[ -x "$PRODUCTS/crosswindctl" ] || build
exec "$PRODUCTS/crosswindctl" "$@"
