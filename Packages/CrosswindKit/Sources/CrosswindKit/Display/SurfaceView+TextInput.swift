// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// NSTextInputClient for a guest surface. macOS input methods (Pinyin, Kana, Hangul, dead keys, the emoji picker)
/// compose here; the results go to the guest, which forwards them to the client over text-input-v3.
extension SurfaceView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        keyConsumedByText = true
        send(textInput.insert(Self.text(string)))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        keyConsumedByText = true
        send(textInput.setMarkedText(Self.text(string), selectedRange: selectedRange))
    }

    func unmarkText() {
        keyConsumedByText = true
        send(textInput.unmark())
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange { textInput.markedRange }

    func hasMarkedText() -> Bool { textInput.hasMarkedText }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// Where the candidate window goes. The guest does not report the caret yet, so this is the view's top-left.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let local = NSRect(x: 0, y: 0, width: 1, height: 1)
        return window.convertToScreen(convert(local, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    private static func text(_ value: Any) -> String {
        (value as? NSAttributedString)?.string ?? (value as? String) ?? ""
    }

    private func send(_ update: TextInputState.Update) {
        guard !update.isEmpty else { return }
        onTextInput?(
            .with {
                if update.deleteBefore > 0 || update.deleteAfter > 0 {
                    $0.deleteSurrounding = .with {
                        $0.before = update.deleteBefore
                        $0.after = update.deleteAfter
                    }
                }
                if let commit = update.commit {
                    $0.commit = .with { $0.text = commit }
                }
                if let preedit = update.preedit {
                    $0.preedit = .with {
                        $0.text = preedit.text
                        $0.cursorBegin = Int32(preedit.cursorBegin)
                        $0.cursorEnd = Int32(preedit.cursorEnd)
                    }
                }
            })
    }
}
