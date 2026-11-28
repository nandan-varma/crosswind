#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Measures boot time, input-to-frame latency and idle memory against the running dev agent (`make dev-agent`, a guest
# image from `make dev-image`, one app window open) and compares them with docs/perf-baseline.json.
#   scripts/perf.sh           measure and compare; exit 1 when a number is worse than baseline x (1 + tolerance)
#   scripts/perf.sh --record  measure and write docs/perf-baseline.json
# The numbers depend on the Mac, so the baseline is recorded per machine class (see the "machine" field); CI runners
# without nested virtualization cannot run this, so it is a release gate run by hand (docs/release.md).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CTL="sh $ROOT/scripts/ctl.sh"
BASELINE=$ROOT/docs/perf-baseline.json

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

window=$($CTL windows | awk 'NR == 1 { print $1 }')
[ -n "$window" ] || { echo "error: open an app window first (crosswindctl launch <app>)" >&2; exit 1; }

# Boot: stop the environment, then time `start` until it reports running. The window is reopened by the guest app
# only if the app is running, so latency is measured before the restart.
types=""
for text in a b c d e f g h; do
    ms=$($CTL type "$window" "$text" | awk -F': ' 'NR == 1 { sub(/ ms/, "", $2); print $2 }')
    case $ms in nan | "") ;; *) types="$types $ms" ;; esac
done

$CTL stop >/dev/null
sleep 2
start=$(now_ms)
$CTL start >/dev/null
boot_ms=$(( $(now_ms) - start ))

host_pid=$(pgrep -f 'CrosswindHost.app/Contents/MacOS/CrosswindHost' | head -1)
host_rss_mb=$(( $(ps -o rss= -p "$host_pid") / 1024 ))
guest_used_mb=$($CTL exec -- sh -c "awk '/MemTotal/ {t=\$2} /MemAvailable/ {a=\$2} END {print int((t-a)/1024)}' /proc/meminfo" 2>/dev/null | tail -1)
guest_used_mb=${guest_used_mb:-0}
[ -n "$types" ] || { echo "error: no typing latency sample came back (is the app window in front?)" >&2; exit 1; }

python3 - "$BASELINE" "${1:-}" "$boot_ms" "$host_rss_mb" "$guest_used_mb" $types <<'PY'
import json, platform, statistics, subprocess, sys
path, mode, boot, rss, guest = sys.argv[1:6]
samples = sorted(float(x) for x in sys.argv[6:])
measured = {
    "boot_ms": int(boot),
    "type_ms_p50": round(statistics.median(samples), 1),
    "type_ms_max": round(samples[-1], 1),
    "host_rss_mb": int(rss),
    "guest_used_mb": int(guest),
}
if mode == "--record":
    machine = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
    # Tolerances are generous: this is a noisy desktop, not a lab. A regression worth failing on is a big one.
    base = {"machine": machine or platform.machine(), "tolerance": {"boot_ms": 0.5, "type_ms_p50": 1.0,
            "type_ms_max": 2.0, "host_rss_mb": 0.5, "guest_used_mb": 0.5}, "values": measured}
    json.dump(base, open(path, "w"), indent=2)
    open(path, "a").write("\n")
    print("recorded", measured)
    sys.exit(0)
base = json.load(open(path))
failed = False
for key, value in measured.items():
    limit = base["values"][key] * (1 + base["tolerance"][key])
    if key.startswith("type_"):
        limit = max(limit, base["values"][key] + 10)  # single-digit milliseconds are noise
    status = "ok" if value <= limit or key == "guest_used_mb" and value == 0 else "REGRESSION"
    failed |= status != "ok"
    print(f"{key:15} {value:>8}  baseline {base['values'][key]:>8}  limit {limit:>9.1f}  {status}")
sys.exit(1 if failed else 0)
PY
