# Crosswind

Crosswind runs Linux GUI apps as native Mac windows. A small Alpine Linux VM runs a Wayland compositor (`crosswindd`), and each Linux window appears as its own macOS window. Apps come from Flathub.

## Status

Early development (Phase 2: app scaffold). The repository builds an app shell, a command-line tool and a test target. The VM, display path and app store are not connected yet.

## Limitations

- No VM boot from the app yet. The guest image is built, but the host does not start it.
- No window streaming yet. The protocol and the host display code exist; they are not wired together.
- The store shell is a placeholder with empty states. Flathub catalog and installs are not implemented.
- `crosswindctl status` always prints `not connected`.
- Apple silicon only, macOS 27 or later.
- Direct distribution (Developer ID). Not for the Mac App Store.
- Keyboard, cursor and clipboard mapping are partial.

## Build

Requirements: macOS 27, Xcode 27, Homebrew, and `xcodegen`, `swiftlint` (`brew install xcodegen swiftlint`). Guest builds also need a Lima VM named `cwbuild` (Alpine aarch64).

```sh
make project   # generate Crosswind.xcodeproj
make build     # app, crosswindctl and tests
make test
make lint
```

Run `make help` for every target. `make image` and `make guest` build the guest in the Lima VM.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
