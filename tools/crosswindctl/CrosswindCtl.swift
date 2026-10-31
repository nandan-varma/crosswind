// SPDX-License-Identifier: AGPL-3.0-or-later
import ArgumentParser

@main
struct CrosswindCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "crosswindctl",
        abstract: "Control the Crosswind host agent.",
        subcommands: [Status.self]
    )
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the host agent connection state.")

    func run() {
        print("not connected")
    }
}
