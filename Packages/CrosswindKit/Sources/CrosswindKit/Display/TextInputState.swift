// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// The composition state behind NSTextInputClient, kept free of AppKit so it can be tested.
///
/// Each mutating call returns the update to send to the guest. Preedit cursor offsets are UTF-8 byte offsets, the
/// convention of `zwp_text_input_v3`; AppKit ranges are UTF-16 offsets.
struct TextInputState: Equatable {
    /// Largest commit or preedit text the host accepts from a guest stub, in UTF-8 bytes.
    static let maxBytes = 4096

    /// One step for the guest, applied in the order delete, commit, preedit (the text-input-v3 `done` order).
    struct Update: Equatable {
        var deleteBefore: UInt32 = 0
        var deleteAfter: UInt32 = 0
        var commit: String?
        var preedit: Preedit?

        var isEmpty: Bool { commit == nil && preedit == nil }
    }

    struct Preedit: Equatable {
        var text: String
        var cursorBegin: Int
        var cursorEnd: Int
    }

    /// The text being composed, or nil when no composition is active.
    private(set) var marked: String?

    var hasMarkedText: Bool { marked != nil }

    var markedRange: NSRange {
        guard let marked else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: marked.utf16.count)
    }

    /// Replaces the composition. An empty string ends it.
    mutating func setMarkedText(_ text: String, selectedRange: NSRange) -> Update {
        guard !text.isEmpty else { return unmark() }
        marked = text
        let utf16 = text.utf16.count
        let cursor = selectedRange.location == NSNotFound ? utf16 : min(selectedRange.location, utf16)
        let end = selectedRange.location == NSNotFound ? utf16 : min(NSMaxRange(selectedRange), utf16)
        return Update(
            preedit: Preedit(
                text: text, cursorBegin: Self.byteOffset(in: text, utf16: cursor),
                cursorEnd: Self.byteOffset(in: text, utf16: end)))
    }

    /// Inserts final text. Ends any composition, whose preedit is cleared in the same update.
    mutating func insert(_ text: String) -> Update {
        let wasComposing = marked != nil
        marked = nil
        return Update(commit: text.isEmpty ? nil : text, preedit: wasComposing ? Self.cleared : nil)
    }

    /// Commits the composition as it stands.
    mutating func unmark() -> Update {
        guard let text = marked else { return Update() }
        marked = nil
        return Update(commit: text, preedit: Self.cleared)
    }

    private static let cleared = Preedit(text: "", cursorBegin: 0, cursorEnd: 0)

    /// UTF-8 byte offset of a UTF-16 offset in `text`, clamped to the string.
    static func byteOffset(in text: String, utf16 offset: Int) -> Int {
        let index = String.Index(utf16Offset: min(max(offset, 0), text.utf16.count), in: text)
        return text[..<index].utf8.count
    }
}
