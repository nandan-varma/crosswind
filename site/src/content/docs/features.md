---
title: Features
description: What Crosswind does today, and what it does not.
group: Use
order: 2
---

## What works

| Area | Details |
| --- | --- |
| Apps | Install, update and uninstall Flathub apps with progress, permissions editor and a built-in store with search and categories. |
| Windows | Each Linux window is a native Mac window: menus and tooltips, minimize, zoom, full screen, size limits, per-app Dock tile and icon. |
| Toolkits | GTK 3 and 4, Qt, Electron and X11 apps. X11 apps run through a rootless XWayland. |
| Input | Keyboard layouts, dead keys and input methods; Command acts as Control; mouse, scroll and cursors. |
| Clipboard | Text, images and HTML in both directions, while a Crosswind app is in front. |
| Drag and drop | Text and files from Mac apps onto Linux windows, and text and shared-folder files out of them. |
| Files and links | Shared folders you grant, native Open and Save dialogs, opening files from Finder (Open With, drops on the Dock icon), and links such as `tg://` or `magnet:` that open in the Linux app. |
| Appearance | Follows light and dark mode. |
| Notifications | Linux notifications appear as Mac notifications from the app. |
| Links | Links in Linux apps open in your Mac browser. |
| Tray icons | StatusNotifier tray icons appear in the menu bar; clicks reach the app. |
| Audio | Sound output; microphone input when you allow it. |
| Resilience | A watchdog restarts a hung Linux environment; idle environments give memory back and stop. |

## What does not work yet

- **GPU acceleration.** The Linux environment renders with the CPU, so OpenGL, Vulkan and WebGL apps are slow or unsupported.
- **Intel-only apps** work in an experimental way through Rosetta; some, such as Electron apps, can crash.
- **Webcams, Bluetooth and USB devices.**

See the [roadmap](/docs/roadmap/) for what is planned and the [compatibility list](/docs/compatibility/) for tested apps.
