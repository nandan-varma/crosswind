---
title: Settings
description: Every setting in Crosswind and what it does.
group: Use
order: 3
---

Open **Crosswind > Settings** (Cmd-,).

## General

| Setting | What it does |
| --- | --- |
| Launch at login | Opens Crosswind when you log in. |
| Command key acts as Control | Uses Cmd for the shortcuts Linux apps expect on Control (copy, paste, undo). On by default. |
| Share the clipboard with Linux apps | Copies text and images between your Mac and Linux apps while a Crosswind app is in front. On by default. |
| Show Linux apps' tray icons in the menu bar | Shows or hides tray icons. Applies at once. |
| Allow Linux apps to use the microphone | Off by default. Applies the next time the environment starts. macOS asks for permission when an app first records. |

## Environment

| Setting | What it does |
| --- | --- |
| Virtual CPUs | How many processor cores the Linux environment can use. |
| Memory | How much memory it can use. Idle environments give memory back. |
| Stop when idle | Stops the environment after this many minutes without apps, windows or installs. "Never" keeps it running. |
| Run Intel apps with Rosetta | Experimental support for apps built only for Intel. Needs Rosetta, which Crosswind can install. |
| Restart Environment | Stops and starts the Linux environment, applying changed settings. |
| Reset Linux Environment | Deletes every installed app and its data. Cannot be undone. |

CPU, memory and Rosetta changes apply the next time the environment starts.

## Storage

Shows the space Crosswind uses, how much of the data disk is filled, and where it lives (`~/Library/Application Support/Crosswind`).

## Shared Folders

The folders Linux apps may read and write. Add one with **Add Folder**, change a folder to read-only, or remove it. A shared folder includes its subfolders. Files you pick in an app's dialog from other places are copied into a temporary share instead.

## About

The version, license, and update settings: check for updates automatically, download them automatically, or check now.
