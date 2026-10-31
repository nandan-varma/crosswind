# 0010: Clipboard and files cross the boundary only on user action

Date: 2026-10-31. Status: accepted.

## Clipboard
- Mac -> Linux is lazy: while a Crosswind app is frontmost the agent announces the pasteboard's MIME types; the data is fetched only when a Linux app pastes (a guest-initiated Call), and only while a stub is frontmost. Text up to 1 MiB, images up to 16 MiB.
- Linux -> Mac is eager (the user just pressed copy): text, PNG and HTML are written to NSPasteboard; echoes are suppressed. A Settings toggle turns the bridge off.
- No custom Spice agent: Apple's Spice agent port needs spice-vdagent in the guest and does not map cleanly to Wayland selections; our messages are small and testable.

## Files
- No host folder is visible to the guest by default. Shared folders are explicit grants (virtiofs tag `mac`, runtime-updated `VZMultipleDirectoryShare`).
- Native Open/Save dialogs come from a portal FileChooser backend: the host shows NSOpenPanel/NSSavePanel; files outside a grant are cloned (APFS clonefile) into a staging share, saves are synced back from staging to the chosen path.
