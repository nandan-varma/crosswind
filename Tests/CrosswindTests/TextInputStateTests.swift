// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Testing

@testable import CrosswindKit

@Test func settingMarkedTextStartsCompositionWithByteOffsets() {
    var state = TextInputState()
    let update = state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
    #expect(state.hasMarkedText)
    #expect(state.markedRange == NSRange(location: 0, length: 2))
    #expect(update.preedit == TextInputState.Preedit(text: "ni", cursorBegin: 2, cursorEnd: 2))
    #expect(update.commit == nil)
}

@Test func cursorOffsetsAreUTF8BytesNotUTF16() {
    var state = TextInputState()
    // "你" is one UTF-16 unit and three UTF-8 bytes; the cursor after it is byte 3.
    let update = state.setMarkedText("你好", selectedRange: NSRange(location: 1, length: 0))
    #expect(update.preedit == TextInputState.Preedit(text: "你好", cursorBegin: 3, cursorEnd: 3))
}

@Test func unknownSelectionPlacesCursorAtEnd() {
    var state = TextInputState()
    let update = state.setMarkedText("ab", selectedRange: NSRange(location: NSNotFound, length: 0))
    #expect(update.preedit?.cursorBegin == 2)
}

@Test func insertCommitsAndClearsComposition() {
    var state = TextInputState()
    _ = state.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
    let update = state.insert("你")
    #expect(!state.hasMarkedText)
    #expect(update.commit == "你")
    #expect(update.preedit == TextInputState.Preedit(text: "", cursorBegin: 0, cursorEnd: 0))
}

@Test func insertWithoutCompositionOnlyCommits() {
    var state = TextInputState()
    let update = state.insert("a")
    #expect(update.commit == "a")
    #expect(update.preedit == nil)
}

@Test func unmarkCommitsTheCompositionAsItStands() {
    var state = TextInputState()
    _ = state.setMarkedText("ka", selectedRange: NSRange(location: 2, length: 0))
    let update = state.unmark()
    #expect(update.commit == "ka")
    #expect(!state.hasMarkedText)
    #expect(state.unmark().isEmpty)
}

@Test func emptyMarkedTextEndsComposition() {
    var state = TextInputState()
    _ = state.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0))
    let update = state.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
    #expect(!state.hasMarkedText)
    #expect(update.commit == nil)
    #expect(update.preedit?.text == "")
}

@Test func noMarkedTextRangeIsNotFound() {
    let state = TextInputState()
    #expect(state.markedRange.location == NSNotFound)
}

@Test func selectionBeyondTheTextIsClamped() {
    var state = TextInputState()
    let update = state.setMarkedText("a", selectedRange: NSRange(location: 5, length: 9))
    #expect(update.preedit == TextInputState.Preedit(text: "a", cursorBegin: 1, cursorEnd: 1))
}
