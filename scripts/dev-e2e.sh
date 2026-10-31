# Development smoke test: build, register the dev agent, install the image, boot, refresh the catalog, install an app.
# Needs a built guest image in ~/.cache/crosswind-img (make image).
cd /Users/nandan/dev/crosswind
make build 2>&1 | tail -1
make dev-agent 2>&1 | tail -1; sleep 1
BP=$(xcodebuild -project Crosswind.xcodeproj -scheme Crosswind -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/ {print $3; exit}')
echo BP=$BP
$BP/crosswindctl stop
make dev-image 2>&1 | tail -1
$BP/crosswindctl status
timeout 120 $BP/crosswindctl start
$BP/crosswindctl status
timeout 300 $BP/crosswindctl catalog refresh
timeout 300 $BP/crosswindctl install org.gnome.Calculator
$BP/crosswindctl installed
echo E2E_DONE
