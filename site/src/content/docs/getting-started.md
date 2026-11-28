---
title: Getting started
description: Install Crosswind, add your first Linux app and learn the basics.
group: Use
order: 1
---

Crosswind runs Linux apps from [Flathub](https://flathub.org) on your Mac. Each app opens in its own native window.

## Requirements

- A Mac with Apple silicon.
- macOS 27 or later.
- About 2 GB of free disk space for the Linux environment, plus room for the apps you install.

## Install Crosswind

Download `Crosswind-0.1.0.dmg` from the [beta release](https://github.com/nandan-varma/crosswind/releases/tag/v0.1.0-beta.2), open it and drag Crosswind to Applications. It is signed and notarized by Apple. You can also build it from source; the [development guide](/docs/development/) walks through it.

## First launch

1. Open **Crosswind**. The first time, macOS asks you to allow its background item under **System Settings > General > Login Items & Extensions**. The background item runs the Linux environment; without it nothing can start.
2. Crosswind downloads the Linux environment image and checks its signature. This happens once.
3. The store opens.

## Install and open an app

1. Browse **Discover**, pick a category or search.
2. Open an app's page and choose **Install**. Flathub apps are downloaded into the Linux environment.
3. Crosswind creates a Mac app for it in `~/Applications/Crosswind` as soon as it is installed, with its own Dock icon, so you can also open it from Spotlight or Launchpad. Choose **Open** to start it.

The Linux environment starts when you open an app and stops after a while without apps. You can change that in [Settings](/docs/settings/).

## Everyday use

- **Windows** behave like Mac windows: resize, minimize, full screen, Cmd-Tab, Mission Control.
- **Shortcuts:** the Command key acts as Control, so Cmd-C, Cmd-V and Cmd-Z work in Linux apps. Cmd-Q quits an app, Cmd-H hides it.
- **Clipboard:** copy and paste work in both directions while a Crosswind app is in front.
- **Files:** to give an app access to a folder, add it under **Settings > Shared Folders**, or pick a file in the app's open dialog and Crosswind asks once. To open a file with an app, use **Open With** in Finder or drop it on the app's Dock icon.
- **Menu bar:** apps with a tray icon, such as chat clients, show it in your menu bar.

If something misbehaves, [the FAQ](/docs/faq/) lists the usual causes.
