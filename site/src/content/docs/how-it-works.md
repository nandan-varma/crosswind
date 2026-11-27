---
title: How it works
description: The three processes, the Linux environment and how windows reach your screen.
group: Reference
order: 5
---

## Three processes

- **Crosswind** is the store app: browse, install, settings.
- **Crosswind Host** is a background agent. It owns the virtual machine, talks to the Linux side and routes windows.
- A small **stub app** per installed Linux app gives it a Dock icon, a menu bar entry and Cmd-Tab presence, and displays its windows.

## The Linux environment

The agent boots an Alpine Linux virtual machine with Apple's Virtualization.framework. The system image is read-only; a separate data disk holds your apps and their data. A daemon, `crosswindd`, runs a Wayland compositor inside the VM.

## Windows

Each Linux window is rendered into memory in the VM. `crosswindd` sends only the changed rectangles, compressed, over a virtio socket. The stub draws them into a native `NSWindow`, and sends keyboard, mouse and focus events back.

## Apps

Apps are Flatpaks, installed with libflatpak into the VM's data disk and run in their own sandboxes. A second channel carries install and launch requests, logs, and requests the Linux side makes of your Mac: file dialogs, notifications, links, clipboard and tray icons.

## What stays isolated

The VM has a NAT network, a read-only system disk, its own data disk, and nothing else unless you share it. Read the [security model](/docs/security/) for the details and the known gaps.
