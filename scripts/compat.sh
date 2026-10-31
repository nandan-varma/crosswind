#!/bin/sh
# Runs the compatibility harness against the running host agent (see `crosswindctl compat run --help`).
# Refreshes docs/compat/{results.json,matrix.md,screenshots/} and App/Store/Resources/CompatRatings.json.
# Usage: scripts/compat.sh [--ids a,b | --set curated] [--timeout 90] [--keep]
# Environment: DERIVED_DATA (build products location, default: Xcode's), CROSSWINDCTL (path to a built binary).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ -n "${CROSSWINDCTL:-}" ]; then
    CTL=$CROSSWINDCTL
else
    products=$(xcodebuild -project "$ROOT/Crosswind.xcodeproj" -scheme Crosswind -configuration Debug \
        ${DERIVED_DATA:+-derivedDataPath "$DERIVED_DATA"} -showBuildSettings \
        | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = / { print $2; exit }')
    CTL="$products/crosswindctl"
fi

if [ ! -x "$CTL" ]; then
    echo "error: $CTL not found; run 'make build' (or set CROSSWINDCTL)" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    set -- --set curated
fi

cd "$ROOT"
exec "$CTL" compat run \
    --dir "$ROOT/docs/compat" \
    --ratings "$ROOT/App/Store/Resources/CompatRatings.json" \
    "$@"
