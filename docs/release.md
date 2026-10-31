# Releases

Crosswind ships outside the Mac App Store as a Developer ID–signed, notarized app in a DMG (team `72CW7UW6RB`). The app is not sandboxed.

## Versioning

- `MARKETING_VERSION` in `project.yml` is the version users see (`0.1.0` today). `scripts/release.sh` reads it and names the DMG `Crosswind-<version>.dmg`.
- `CURRENT_PROJECT_VERSION` is the build number. Bump it for every build you publish.
- Tag the release `v<version>` on the commit that was built.

## Parts of a release

- **App**: `Crosswind.app` contains the store app, `CrosswindHost.app` (in `Contents/Library/Helpers`, the background agent with `com.apple.security.virtualization`), `CrosswindAppStub.app` (in `Contents/Resources`, the template for per-app stubs) and `crosswindctl` (in `Contents/MacOS`).
- **Guest image**: `Image`, `initramfs`, `system.erofs` and `SHA256SUMS`, built in the Lima VM by `make image` into `~/.cache/crosswind-img`.
- **Manifest**: `scripts/image-manifest.sh <image-dir> <version> <base-url>` writes `GuestImage.json`, which lists each file's size, SHA-256 and URL. `crosswindctl image install <GuestImage.json>` installs it.
- **Target layout (not implemented)**: the image and `GuestImage.json` are meant to ship inside the app at `Contents/Resources`, so a release is self-contained. Today the release script does not bundle them.

## Building a release

```sh
make release                 # full release: archive, export, verify, notarize, DMG
NOTARIZE=0 make release      # signed app only: no notarization, no DMG
```

`scripts/release.sh` does this, in order:

1. `xcodegen generate`.
2. `xcodebuild archive` (Release, scheme `Crosswind`, manual signing). It passes `RELEASE_SIGN="Developer ID Application"`, `ENABLE_HARDENED_RUNTIME=YES` and `OTHER_CODE_SIGN_FLAGS=--timestamp`.
3. `xcodebuild -exportArchive` with `ExportOptions.plist` (method `developer-id`).
4. Checks every signed binary (the app, `CrosswindHost`, `CrosswindAppStub`, `crosswindctl`): the Developer ID authority, the hardened runtime, a secure timestamp and no `get-task-allow`. It also checks `codesign --verify --deep --strict` and that `CrosswindHost` has `com.apple.security.virtualization`.
5. `helpers sign notarize` on the app (this also staples the ticket).
6. Builds `build/release/Crosswind-<version>.dmg` with `hdiutil` (volume `Crosswind`, with an `/Applications` link), then notarizes and staples it.
7. `helpers sign verify` on the DMG.

Output goes to `build/release/`: the archive, the `export/` directory and the DMG. Nothing is committed or uploaded.

The stub template must stay Developer ID signed. `StubInstaller` re-signs the per-app copies it generates ad hoc, so the template's signature does not carry over to them.

## Local install

`make install-local` (`scripts/install-local.sh`) builds with `NOTARIZE=0`, stops a running Crosswind and `CrosswindHost` (`scripts/dev-agent.sh uninstall`), replaces `/Applications/Crosswind.app`, installs the guest image from `~/.cache/crosswind-img` with `crosswindctl image install`, and opens the app. It needs `make image` to have run first.

## Publishing on GitHub

Not automated. The steps are manual:

```sh
make release
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 build/release/Crosswind-0.1.0.dmg \
  --title "Crosswind 0.1.0" --notes-file <notes.md>
helpers sign verify <owner>/<repo>@v0.1.0    # checks the release assets as users get them
```

Add the guest image and `GuestImage.json` as release assets too, once the image is built for the release.

## Notarization

`helpers sign notarize` submits with the App Store Connect API key (`ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`) and waits for Apple. It staples the ticket when Apple accepts it. Apple's issues are printed when it rejects a submission. The common causes are a missing timestamp, a missing hardened runtime, unsigned nested code and `get-task-allow`. A disk image is unsigned by design. What counts is its stapled ticket and the app inside it.

## Not automated yet

- Bumping `CURRENT_PROJECT_VERSION` and tagging.
- Bundling the guest image and `GuestImage.json` into the app at `Contents/Resources`.
- Creating the GitHub release, its notes and its assets.
- A CI workflow (`helpers sign guide ci` describes one).
- Sparkle or any other in-app update path.
- Release-time testing of the installed app. The checks above are signing and notarization checks only.
