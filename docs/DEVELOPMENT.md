# Development guide

How to build Crosswind, run it against a live guest, and debug it. `CLAUDE.md` and `CONTRIBUTING.md` hold the rules;
this file holds the procedures.

## One-time setup

1. Tools: Xcode 27, Homebrew, `brew install xcodegen swiftlint lima protobuf`.
2. The guest build VM. Alpine aarch64 under Lima, named `cwbuild` (the Makefile default):

   ```sh
   limactl create --name cwbuild --tty=false --vm-type vz --cpus 4 --memory 6 --disk 30 --mount-writable template:alpine
   limactl start cwbuild
   limactl shell cwbuild sudo apk add --no-cache rust cargo protobuf protobuf-dev build-base erofs-utils git \
     pkgconf glib-dev flatpak-dev ostree-dev libxkbcommon-dev libxcb-dev xcb-util-cursor-dev clang clang-dev \
     pipewire-dev alsa-lib-dev eudev-dev libinput-dev mesa-dev libseat-dev pixman-dev
   ```

3. `make image` builds `crosswindd`, `xwayland-satellite` and the guest image, and copies it to
   `~/.cache/crosswind-img/`. `make dev-image` installs that image where the app looks for it.

## The development loop

```sh
make dev-agent            # build and register the host agent (debug mode on, see below)
sh scripts/ctl.sh start   # boot the guest
sh scripts/ctl.sh install org.gnome.Calculator
sh scripts/ctl.sh launch org.gnome.Calculator
sh scripts/ctl.sh windows
```

`scripts/ctl.sh` runs `crosswindctl` from `build/dd`, a project-local build, and builds it when missing. Xcode's
DerivedData is not used because cleaning tools delete it and strand the registered agent. After changing Swift code,
`sh scripts/ctl.sh --rebuild` rebuilds and registers the agent again. After changing the guest, `make image` then
`make dev-image`, then `sh scripts/ctl.sh stop` and `start` (the image is read when the VM boots).

A window needs a stub to be shown: `crosswindctl stub add <app-id> <name> --template <CrosswindAppStub.app>`, then
`open ~/Applications/Crosswind/<name>.app`. The compatibility harness does this headlessly.

## Debug mode

`make dev-agent` registers the agent with `CROSSWIND_DEBUG=1`. Only a debug agent:

- boots the guest with `crosswind.debug=1` on the kernel command line, and
- lets `crosswindctl` send `DebugExec` requests, which the guest accepts only under that flag.

```sh
sh scripts/ctl.sh exec -- flatpak --user list --app
sh scripts/ctl.sh exec --timeout 60 -- sh -c 'flatpak --user run org.videolan.VLC 2>&1 | head'
```

Commands run as the daemon's user (uid 1000) with the environment app launches get (Wayland, session bus, `DISPLAY`).
A shipped agent has no such variable, so the guest refuses the request. `make image DEBUG_TOOLS=1` adds `strace`,
`lsof` and `ps` from `image/packages.debug`; they are never part of a release image.

Useful techniques learned the hard way:

- **Logs:** `crosswindctl logs --since 60`, and `log stream --predicate 'subsystem == "dev.crosswind"'` for the host.
- **Tracing an app:** run it under `strace -f -o /tmp/s.log -e trace=execve,sendmsg,recvmsg flatpak --user run <id>`
  through `exec`. Yama's `ptrace_scope=1` allows attaching only to your own descendants, so start the process under
  strace instead of attaching to a running one.
- **Everything the portal does:** kill `flatpak-portal`, then run `strace -f /usr/libexec/flatpak-portal` as your own
  child; D-Bus hands it the name. This is how the Electron zygote failure was found (see `docs/KNOWLEDGE.md`).
- Use `pidof` to find processes. `pkill -f` and `ps | grep` patterns match the shell running them.
- Capture one window, not the screen, when taking screenshots: other windows on the Mac are private.

## Checks

`make lint` (SwiftLint and `swift-format`, check only), `make test` (app tests) and
`cd Packages/CrosswindKit && swift test` (package tests) must pass. Guest: `cargo test --release` in `guest/` inside
the VM. `make format` rewrites Swift sources; run it, then review the diff before committing, because it also touches
`Package.swift`.
