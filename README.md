# Crosswind

Crosswind runs Linux GUI apps as native Mac windows. A small Alpine Linux VM runs a Wayland compositor (`crosswindd`), and each Linux window appears as its own macOS window. Apps come from Flathub.

## Status

Pre-release, working end to end. Flathub apps install from the store, run in the VM and appear as native Mac windows with their own Dock tiles. Integrations built so far: clipboard, audio output and opt-in microphone, notifications, dark mode, opening links, shared folders with native file dialogs, X11 apps through XWayland, keyboard layouts and input methods, and window management. Which apps work is recorded in [docs/compat/matrix.md](docs/compat/matrix.md); what is open is in [docs/ROADMAP.md](docs/ROADMAP.md).

Documentation and the project homepage: https://crosswind.nandan.fyi (source in [site/](site/)).

## Limitations

- Apple silicon only, macOS 27 or later.
- The guest renders on the CPU. There is no GPU acceleration, so OpenGL, Vulkan and WebGL apps are slow or unsupported.
- Only apps with an arm64 build on Flathub run. x86-only apps are not supported yet.
- No webcam or Bluetooth yet.
- Direct distribution (Developer ID). Not for the Mac App Store.

## Architecture

Three processes: the store app (`Crosswind`), a background agent (`CrosswindHost`) that owns the VM, and a small stub per installed app that gives it a Dock tile and shows its windows. Inside the guest, `crosswindd` is a Wayland compositor that streams per-window damage to the host. See [CLAUDE.md](CLAUDE.md) and [docs/adr](docs/adr).

## Build

Requirements: macOS 27, Xcode 27, Homebrew, and `xcodegen`, `swiftlint` (`brew install xcodegen swiftlint`). Guest builds also need a Lima VM named `cwbuild` (Alpine aarch64).

```sh
make project   # generate Crosswind.xcodeproj
make build     # app, crosswindctl and tests
make test
make lint
```

Run `make help` for every target. `make image` and `make guest` build the guest in the Lima VM. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers the VM setup, running against a live guest and the debugging tools.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
