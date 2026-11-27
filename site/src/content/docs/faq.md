---
title: FAQ
description: Common questions and fixes.
group: Use
order: 4
---

## Why does Crosswind use a virtual machine?

Linux apps need a Linux kernel and libraries. A VM runs them unchanged and keeps them away from the rest of your Mac.

## Does it use a lot of memory?

The Linux environment starts when you open an app, gives memory back when idle and stops after a while without apps. You can set the limits in [Settings](/docs/settings/).

## An app I want is missing.

Crosswind lists Flathub apps that have an Apple silicon (arm64) build. Intel-only apps need Rosetta support, which is experimental; turn it on under Settings > Environment.

## An app is slow or draws wrongly.

The Linux environment has no GPU acceleration yet, so apps that depend on OpenGL, Vulkan or WebGL are slow. The [compatibility list](/docs/compatibility/) notes what was tested.

## I do not see my files.

Linux apps only see the folders you share. Add one under Settings > Shared Folders, or pick the file in the app's dialog and choose to share it.

## What is the terminal in Kate or other apps?

A shell inside the Linux environment, not on your Mac. It sees the Linux apps and the shared folders only.

## An app asks for notification permission.

macOS asks once per app, because each Linux app is its own Mac app. Allow it in the prompt or in System Settings > Notifications.

## How do I remove an app or everything?

Uninstall an app from its page in the store. To remove all apps and their data, use **Reset Linux Environment** in Settings.

## It stopped responding.

If the Linux environment hangs, Crosswind notices, stops it and shows **Restart Linux Environment** in the menu bar item. **Restart Environment** in Settings does the same.

## Where do I report a problem?

On [GitHub](https://github.com/nandan-varma/crosswind/issues). **Diagnostics** in the store app builds a report with personal data removed.
