# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- First end-to-end build: Linux apps from Flathub run as native Mac windows with their own Dock tiles (see docs/ROADMAP.md for what is verified and what is open).

### Added

- XcodeGen project (`project.yml`) with the `Crosswind` app, the `crosswindctl` tool and the `CrosswindTests` unit tests.
- Placeholder store shell (Discover, Installed, Updates) in the app.
- `crosswindctl status` stub.
- `Makefile` with build, test, lint, format, proto, guest and image targets.
- SwiftLint and `swift-format` configuration.
- GitHub Actions CI for the macOS app and the Linux arm64 guest.
