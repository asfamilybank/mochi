import AppKit
import Testing

@testable import MochiCore

/// AppKit delivers a tracking area's events to its owner by the selectors `mouseEntered:` and
/// `mouseExited:`. Declared on a plain `NSObject` as `mouseEntered(with:)`, Swift names the method
/// `mouseEnteredWith:` instead, and every event is dropped without a word — the address field's
/// hover and Float Mode's title bar both stayed dead that way.
@Suite struct HoverTrackerTests {
    @Test(arguments: ["mouseEntered:", "mouseExited:"])
    func answersTheSelectorAppKitSends(_ selector: String) {
        #expect(HoverTracker().responds(to: NSSelectorFromString(selector)))
    }

    @Test func forwardsAnEnterAndAnExitToItsClosures() throws {
        let tracker = HoverTracker()
        var calls: [String] = []
        tracker.onEnter = { calls.append("enter") }
        tracker.onExit = { calls.append("exit") }
        let event = try #require(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))

        tracker.perform(NSSelectorFromString("mouseEntered:"), with: event)
        tracker.perform(NSSelectorFromString("mouseExited:"), with: event)

        #expect(calls == ["enter", "exit"])
    }
}
