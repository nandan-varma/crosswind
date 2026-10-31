# Releases

Crosswind ships outside the Mac App Store as a Developer ID–signed, notarized app in a DMG (team `72CW7UW6RB`). The app is not sandboxed.

## Versioning

- `MARKETING_VERSION` in `project.yml` is the version users see (`0.1.0` today). `scripts/release.sh` reads it and names the DMG `Crosswind-<version>.dmg`.
- `CURRENT_PROJECT_VERSION` is the build number. Bump it for every build you publish.
- Tag the release `v<version>` on the commit that was built.

## Parts of a release

- **App**: `Crosswind.app` contains the store app, `CrosswindHost.app` (in `Contents/Library/Helpers`, the background agent with `com.apple.security.virtualization`), `CrosswindAppStub.app` (in `Contents/Resources`, the template for per-app stubs) and `crosswindctl` (in `Contents/MacOS`).
- **Guest image**: `Image`, `initramfs`, `system.erofs` and `SHA256SUMS`, built in the Lima VM by `make image` into `~/.cache/crosswind-img`.
- **Manifest**: `scripts/image-manifest.sh <image-dir> <version> <base-url>` writes `GuestImage.json`, which lists each file's size, SHA-256 and URL. `crosswindctl image install <GuestImage.json>` installs it by hand.
- **Embedded manifest**: `scripts/release.sh` embeds `GuestImage.json` in `Crosswind.app/Contents/Resources` when you give it an image directory and the base URL the files will be served from:

  ```sh
  IMAGE_DIR=~/.cache/crosswind-img \
  IMAGE_BASE_URL=https://github.com/nandan-varma/crosswind/releases/download/v0.1.0 \
  NOTARIZE=0 sh scripts/release.sh
  ```

  `IMAGE_DIR` must contain `SHA256SUMS` (from `make image`). Set both variables or neither. `IMAGE_VERSION` sets the manifest version; by default it is the first 12 hex digits of the SHA-256 of `SHA256SUMS`, so a rebuilt image gets a new version and an unchanged one keeps its version. The script writes the manifest to `build/GuestImage.json`, a post-build phase copies it into the app, and the script deletes it afterwards. Without both variables the app is built with no manifest and the release output says so: the store app then installs no guest image.
- **Image updates**: when the bundled manifest's version differs from the installed `VERSION`, the store app stops the VM, then downloads the new files into a staging directory, verifies each size and SHA-256, and swaps the directories by rename. If any download or check fails, the old image stays installed. The user's data disk (`data.img`) is never touched. The setup view shows "Updating Linux environment…" while this runs.

## Building a release

```sh
make release                 # full release: archive, export, verify, notarize, DMG
NOTARIZE=0 make release      # signed app only: no notarization, no DMG
```

`scripts/release.sh` does this, in order:

1. Writes `build/GuestImage.json` when `IMAGE_DIR` and `IMAGE_BASE_URL` are set (see above).
2. `xcodegen generate`.
3. `xcodebuild archive` (Release, scheme `Crosswind`, manual signing). It passes `RELEASE_SIGN="Developer ID Application"`, `ENABLE_HARDENED_RUNTIME=YES` and `OTHER_CODE_SIGN_FLAGS=--timestamp`.
4. `xcodebuild -exportArchive` with `ExportOptions.plist` (method `developer-id`).
5. Checks every signed binary (the app, `CrosswindHost`, `CrosswindAppStub`, `crosswindctl`, and Sparkle's `Sparkle` binary, `Autoupdate`, `Updater.app`, and the `Installer.xpc` and `Downloader.xpc` services): the Developer ID authority, the hardened runtime, a secure timestamp and no `get-task-allow`. It also checks `codesign --verify --deep --strict` on the app and `--strict` on `Sparkle.framework`, and that `CrosswindHost` has `com.apple.security.virtualization`.
6. `helpers sign notarize` on the app (this also staples the ticket).
7. Builds `build/release/Crosswind-<version>.dmg` with `hdiutil` (volume `Crosswind`, with an `/Applications` link), then notarizes and staples it.
8. `helpers sign verify` on the DMG.

Output goes to `build/release/`: the archive, the `export/` directory and the DMG. Nothing is committed or uploaded.

With `NOTARIZE=0` the script stops after the signature checks, so `build/release/export/Crosswind.app` is a signed app with no DMG.

The stub template must stay Developer ID signed. `StubInstaller` re-signs the per-app copies it generates ad hoc, so the template's signature does not carry over to them.

## Local install

`make install-local` (`scripts/install-local.sh`) builds with `NOTARIZE=0`, stops a running Crosswind and `CrosswindHost` (`scripts/dev-agent.sh uninstall`), replaces `/Applications/Crosswind.app`, installs the guest image from `~/.cache/crosswind-img` with `crosswindctl image install`, and opens the app. It needs `make image` to have run first.

## App updates (Sparkle)

The store app updates itself with [Sparkle 2](https://sparkle-project.org) (`Sparkle` package in `project.yml`, pinned to 2.10.1, for the `Crosswind` target only). The feed is `SUFeedURL` in `project.yml`, which points at `releases/latest/download/appcast.xml`: the appcast must be an asset of the latest GitHub release. Automatic checks are on by default (`SUEnableAutomaticChecks`); `SUEnableSystemProfiling` is `NO`, so Sparkle sends no system profile. The menu item is Crosswind › Check for Updates….

**EdDSA keys.** Every update is signed with an EdDSA key. The public key is `SUPublicEDKey` in `project.yml`. The private key lives in the login keychain of the machine that signs releases, under Sparkle's default account. Keep a backup in a password manager; losing it means existing installs cannot be updated and the public key has to change. Never commit or print the private key. To create one on a new machine (only if you have none), run Sparkle's `generate_keys`; it prints the public key. `generate_keys -p` prints the stored public key again.

**Appcast.** After `scripts/release.sh` produces the DMG:

```sh
scripts/appcast.sh build/release/Crosswind-0.1.0.dmg [previous-appcast.xml]
```

This runs Sparkle's `generate_appcast` on a copy of the DMG in `build/appcast/`. It signs the enclosure with the keychain key and writes `build/appcast/appcast.xml`. Pass the appcast of the last release as the second argument so older entries are kept. The enclosures point at `https://github.com/nandan-varma/crosswind/releases/download/v<version>/`. The script finds Sparkle's tools in `SPARKLE_BIN`, in any Xcode DerivedData, or in `/tmp/dd-compat`. Set `SPARKLE_BIN` to `<derived-data>/SourcePackages/artifacts/sparkle/Sparkle/bin` when they are elsewhere. The script publishes nothing.

## Publishing on GitHub

Not automated. The steps are manual:

```sh
IMAGE_DIR=~/.cache/crosswind-img IMAGE_BASE_URL=<base-url> make release   # or NOTARIZE=0 sh scripts/release.sh
scripts/appcast.sh build/release/Crosswind-0.1.0.dmg <previous-appcast.xml>
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 build/release/Crosswind-0.1.0.dmg build/appcast/appcast.xml \
  --title "Crosswind 0.1.0" --notes-file <notes.md>
helpers sign verify <owner>/<repo>@v0.1.0    # checks the release assets as users get them
```

Attach the guest image files as release assets too when `IMAGE_BASE_URL` points at this release. `appcast.xml` must be an asset of the release marked as latest, because `SUFeedURL` resolves through `releases/latest`.

## Notarization

`helpers sign notarize` submits with the App Store Connect API key (`ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`) and waits for Apple. It staples the ticket when Apple accepts it. Apple's issues are printed when it rejects a submission. The common causes are a missing timestamp, a missing hardened runtime, unsigned nested code and `get-task-allow`. A disk image is unsigned by design. What counts is its stapled ticket and the app inside it.

## Not automated yet

- Bumping `CURRENT_PROJECT_VERSION` and tagging.
- Bundling the guest image and `GuestImage.json` into the app at `Contents/Resources`.
- Creating the GitHub release, its notes and its assets.
- A CI workflow (`helpers sign guide ci` describes one).
- Signing and publishing the appcast: `scripts/appcast.sh` only writes it.
- Release-time testing of the installed app. The checks above are signing and notarization checks only.

## Archive gotcha: SKIP_INSTALL

Xcode 27 refuses to export an archive with several installable products ("doesn't support distributing archive").
`project.yml` therefore sets `SKIP_INSTALL: YES` on CrosswindHost, CrosswindAppStub and crosswindctl (they are embedded
into Crosswind.app) and `SKIP_INSTALL: NO` with `INSTALL_PATH: /Applications` on Crosswind. Keep it that way for any new
embedded target.
