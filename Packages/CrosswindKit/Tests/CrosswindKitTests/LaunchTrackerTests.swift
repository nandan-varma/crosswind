// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import CrosswindKit

@Suite struct LaunchTrackerTests {
    @Test func aSingleLaunchQuitsWhenItExits() {
        var tracker = LaunchTracker()
        tracker.started(appID: "a", launchID: "1")
        #expect(tracker.isRunning("a"))
        let quit = tracker.exited(appID: "a", launchID: "1")
        #expect(quit)
        #expect(!tracker.isRunning("a"))
    }

    @Test func aForwardingLaunchExitingDoesNotQuitTheApp() {
        var tracker = LaunchTracker()
        tracker.started(appID: "a", launchID: "main")
        tracker.started(appID: "a", launchID: "forward")
        let forwardQuit = tracker.exited(appID: "a", launchID: "forward")
        #expect(!forwardQuit)
        #expect(tracker.isRunning("a"))
        let mainQuit = tracker.exited(appID: "a", launchID: "main")
        #expect(mainQuit)
    }

    @Test func appsAreTrackedIndependentlyAndListedSorted() {
        var tracker = LaunchTracker()
        tracker.started(appID: "b", launchID: "1")
        tracker.started(appID: "a", launchID: "2")
        #expect(tracker.runningApps == ["a", "b"])
        tracker.exited(appID: "a", launchID: "2")
        #expect(tracker.runningApps == ["b"])
    }

    @Test func anUnknownExitIsNotAQuit() {
        var tracker = LaunchTracker()
        let quit = tracker.exited(appID: "a", launchID: "1")
        #expect(!quit)
    }
}
