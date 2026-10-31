// SPDX-License-Identifier: AGPL-3.0-or-later
import os

/// One subsystem, one category per layer; `log stream --predicate 'subsystem == "dev.crosswind"'`.
public enum Log {
    public static let vm = Logger(subsystem: "dev.crosswind", category: "vm")
    public static let display = Logger(subsystem: "dev.crosswind", category: "display")
    public static let input = Logger(subsystem: "dev.crosswind", category: "input")
    public static let store = Logger(subsystem: "dev.crosswind", category: "store")
    public static let flatpak = Logger(subsystem: "dev.crosswind", category: "flatpak")
    public static let ui = Logger(subsystem: "dev.crosswind", category: "ui")

    public static let signposter = OSSignposter(subsystem: "dev.crosswind", category: "perf")
}
