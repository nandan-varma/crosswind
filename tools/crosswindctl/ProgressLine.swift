// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Prints progress the way the output goes: one rewritten line on a terminal, a line per 10% when piped to a file or
/// another program (so logs do not fill with one entry per percent).
struct ProgressLine {
    private let interactive = isatty(STDOUT_FILENO) != 0
    private var lastStep = -1

    mutating func update(percent: Int, detail: String = "") {
        let suffix = detail.isEmpty ? "" : " \(detail)"
        if interactive {
            print("\r\(percent)%\(suffix)", terminator: "")
            fflush(stdout)
        } else if percent / 10 != lastStep {
            lastStep = percent / 10
            print("\(percent)%\(suffix)")
        }
    }

    /// Ends the progress with a final message on its own line.
    func finish(_ message: String) {
        print(interactive ? "\r\(message)\u{1B}[K" : message)
    }
}
