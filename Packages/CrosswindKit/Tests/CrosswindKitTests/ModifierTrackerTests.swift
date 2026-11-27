// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Testing

@testable import CrosswindKit

@Suite struct ModifierTrackerTests {
    private let leftCommand: UInt16 = 55
    private let leftShift: UInt16 = 56

    @Test func aHeldModifierTheGuestNeverHeardAboutIsPressed() {
        var tracker = ModifierTracker()
        let transitions = tracker.reconcile(with: [.command])
        #expect(transitions == [.init(code: leftCommand, pressed: true)])
    }

    @Test func modifiersThatAgreeProduceNothing() {
        var tracker = ModifierTracker()
        tracker.record(code: leftCommand, pressed: true)
        #expect(tracker.reconcile(with: [.command]).isEmpty)
        #expect(tracker.reconcile(with: [.command]).isEmpty)
    }

    @Test func aModifierReleasedWhileAwayIsReleasedOnTheNextKey() {
        var tracker = ModifierTracker()
        tracker.record(code: leftCommand, pressed: true)
        let transitions = tracker.reconcile(with: [])
        #expect(transitions == [.init(code: leftCommand, pressed: false)])
        #expect(tracker.held.isEmpty)
    }

    @Test func rightHandedModifiersAreNotDoubled() {
        var tracker = ModifierTracker()
        tracker.record(code: 54, pressed: true)  // right command
        #expect(tracker.reconcile(with: [.command]).isEmpty)
    }

    @Test func eachCategoryIsReconciledIndependently() {
        var tracker = ModifierTracker()
        tracker.record(code: leftShift, pressed: true)
        let transitions = tracker.reconcile(with: [.command])
        #expect(transitions.contains(.init(code: leftShift, pressed: false)))
        #expect(transitions.contains(.init(code: leftCommand, pressed: true)))
    }

    @Test func releaseAllReleasesEverythingHeldOnce() {
        var tracker = ModifierTracker()
        tracker.record(code: leftCommand, pressed: true)
        tracker.record(code: leftShift, pressed: true)
        let released = tracker.releaseAll()
        #expect(released.count == 2)
        #expect(released.allSatisfy { !$0.pressed })
        #expect(tracker.releaseAll().isEmpty)
    }
}
