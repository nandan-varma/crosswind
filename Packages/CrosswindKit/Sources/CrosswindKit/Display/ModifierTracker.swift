// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Which modifier keys the guest believes are held, kept in step with the Mac.
///
/// The guest learns about modifiers only from the key events the view sends. Those can fall out of step with the
/// Mac: a modifier released while the window is not key (Cmd-Tab away with Command down) never reports a release,
/// and synthetic or remapped events can carry modifier flags with no `flagsChanged` before them. A modifier the guest
/// still holds then turns every later key into a shortcut. The tracker compares what the guest holds with what each
/// key event says is held and returns the presses and releases that make them agree.
struct ModifierTracker {
    /// A key press or release to send to the guest, by macOS key code.
    struct Transition: Equatable {
        let code: UInt16
        let pressed: Bool
    }

    private struct Category {
        let flag: NSEvent.ModifierFlags
        let codes: [UInt16]  // left first
    }

    private static let categories = [
        Category(flag: .shift, codes: [56, 60]),
        Category(flag: .control, codes: [59, 62]),
        Category(flag: .option, codes: [58, 61]),
        Category(flag: .command, codes: [55, 54]),
    ]

    private(set) var held: Set<UInt16> = []

    /// Records a modifier key the view reported through `flagsChanged`.
    mutating func record(code: UInt16, pressed: Bool) {
        if pressed { held.insert(code) } else { held.remove(code) }
    }

    /// The transitions that make the guest's modifiers match `flags` (the Mac's, from the current key event).
    mutating func reconcile(with flags: NSEvent.ModifierFlags) -> [Transition] {
        var transitions: [Transition] = []
        for category in Self.categories {
            let heldCodes = category.codes.filter(held.contains)
            if flags.contains(category.flag), heldCodes.isEmpty, let left = category.codes.first {
                held.insert(left)
                transitions.append(Transition(code: left, pressed: true))
            } else if !flags.contains(category.flag) {
                for code in heldCodes {
                    held.remove(code)
                    transitions.append(Transition(code: code, pressed: false))
                }
            }
        }
        return transitions
    }

    /// Releases everything held, for when the window stops being key.
    mutating func releaseAll() -> [Transition] {
        defer { held.removeAll() }
        return held.sorted().map { Transition(code: $0, pressed: false) }
    }
}
