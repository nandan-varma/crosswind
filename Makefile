# Crosswind developer commands. Run `make help` for the list.

.DEFAULT_GOAL := help
.PHONY: help project build test lint format proto image guest

# Lima VM with the Alpine aarch64 build environment (see image/build.sh).
LIMA_VM ?= cwbuild
CW_TARGET ?= /tmp/cw-target
IMG_OUT ?= /tmp/cw-image
IMG_CACHE ?= $(HOME)/.cache/crosswind-img
IMG_FILES := Image initramfs system.erofs SHA256SUMS

SCHEME ?= Crosswind
SWIFT_SOURCES := $(shell find App tools Tests Packages -name '*.swift' -not -path '*/Generated/*' -not -path '*/.build/*')
HAVE_HELPERS := $(shell command -v helpers >/dev/null 2>&1 && echo 1)

help: ## Show this list
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  %-8s %s\n", $$1, $$2 }'

project: ## Generate Crosswind.xcodeproj from project.yml
	xcodegen generate

build: project ## Build the app, crosswindctl and the tests (helpers xcode when installed, else xcodebuild)
ifeq ($(HAVE_HELPERS),1)
	helpers xcode build --opts '{"scheme":"$(SCHEME)"}'
else
	xcodebuild -project Crosswind.xcodeproj -scheme $(SCHEME) -destination 'platform=macOS' build
endif

test: project ## Run the CrosswindTests unit tests
ifeq ($(HAVE_HELPERS),1)
	helpers xcode test --opts '{"scheme":"$(SCHEME)"}'
else
	xcodebuild -project Crosswind.xcodeproj -scheme $(SCHEME) -destination 'platform=macOS' test
endif

lint: ## Check SwiftLint and swift-format (no changes written)
	swiftlint lint --strict $(SWIFT_SOURCES)
	xcrun swift-format lint --strict --recursive $(SWIFT_SOURCES)

format: ## Rewrite Swift sources with swift-format
	xcrun swift-format format --in-place $(SWIFT_SOURCES)

proto: ## Regenerate Swift protobuf bindings from proto/
	sh scripts/proto.sh

guest: ## Build crosswindd (release) inside the Lima VM
	limactl shell $(LIMA_VM) sh -c 'cd "$(CURDIR)/guest" && CARGO_TARGET_DIR=$(CW_TARGET) cargo build --release'

image: guest ## Build the guest image in the Lima VM and copy it to ~/.cache/crosswind-img
	limactl shell $(LIMA_VM) sh -c 'cd "$(CURDIR)" && sudo CROSSWINDD=$(CW_TARGET)/release/crosswindd OUT=$(IMG_OUT) sh image/build.sh'
	mkdir -p "$(IMG_CACHE)"
	for f in $(IMG_FILES); do limactl copy $(LIMA_VM):$(IMG_OUT)/$$f "$(IMG_CACHE)/"; done
