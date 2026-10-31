# 0008: Three process types: host agent, store, per-app stubs

Date: 2026-10-31. Status: accepted. Evidence: end-to-end run (Calculator Flatpak as its own Mac app with its own menu bar identity).

## Context
macOS gives one Dock tile and one Cmd-Tab entry per process. Each Linux app must look like its own Mac app, and apps must survive quitting the store.

## Decision
- `CrosswindHost` (LaunchAgent, accessory app): owns the VM, both vsock channels and routing. launchd starts it on demand through the Mach service `dev.crosswind.host`.
- `Crosswind` (store): SwiftUI; talks to the agent as role STORE.
- `CrosswindAppStub`: one generated, ad-hoc-signed copy per installed app in ~/Applications/Crosswind (Spotlight/Launchpad index it). It hosts that app's NSWindows and connects as role STUB with its Flatpak id.
- XPC only does the handshake (role and app id travel there); the agent hands the client one end of a socketpair and the framed protobuf protocol runs on it (agent.proto). Stubs can only launch their own app and only send input for windows they own; only crosswindctl may inject input.

## Consequences
Each stub decodes its own frames (no pixel sharing across processes needed). Stubs are ad-hoc signed locally, so they cannot be authenticated by team id: the trust boundary is the same-user local session (docs/security.md).
Revisit when: stub authentication by cdhash registry becomes necessary, or window counts make per-stub memory a problem.
