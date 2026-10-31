#!/bin/sh
# Development registration of the CrosswindHost agent from the built Debug products.
# Usage: scripts/dev-agent.sh install|uninstall|status
set -eu

LABEL=dev.crosswind.host
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

built_products_dir() {
    xcodebuild -project "$ROOT/Crosswind.xcodeproj" -scheme Crosswind -configuration Debug -showBuildSettings \
        | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = / { print $2; exit }'
}

loaded() {
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1
}

unload() {
    if loaded; then
        launchctl bootout "$DOMAIN/$LABEL"
        # bootout returns before the service is gone; bootstrapping too early fails with an I/O error.
        for _ in 1 2 3 4 5 6 7 8 9 10; do loaded || break; sleep 0.5; done
    fi
}

install() {
    dir=$(built_products_dir)
    exe="$dir/CrosswindHost.app/Contents/MacOS/CrosswindHost"
    if [ ! -x "$exe" ]; then
        echo "error: $exe not found; run 'make build' first" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$exe</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>$LABEL</key>
        <true/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST_EOF
    unload
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Registered $LABEL from $exe"
    logs_hint
}

uninstall() {
    unload
    rm -f "$PLIST"
    echo "Unregistered $LABEL"
}

status() {
    if loaded; then
        echo "$LABEL: loaded"
        launchctl print "$DOMAIN/$LABEL" | grep -E 'program|pid|state' || true
    else
        echo "$LABEL: not loaded"
    fi
    if [ -f "$PLIST" ]; then echo "plist: $PLIST"; else echo "plist: absent"; fi
}

logs_hint() {
    echo "Logs: log stream --predicate 'subsystem == \"dev.crosswind\"'"
}

case "${1:-}" in
    install) install ;;
    uninstall) uninstall ;;
    status) status ;;
    *) echo "usage: $0 install|uninstall|status" >&2; exit 2 ;;
esac
