import Foundation
import Testing

@testable import MochiCore

/// All four Carbon modifier flags stacked together (cmd|shift|option|control) plus an F-key —
/// combinations real apps essentially never claim, to keep these tests from colliding with an
/// actual system-wide hotkey while they exercise the real `RegisterEventHotKey`/
/// `UnregisterEventHotKey` calls.
private let testHotkeyA = Hotkey(keyCode: 0x69 /* F13 */, modifierFlags: 0x1B00)
private let testHotkeyB = Hotkey(keyCode: 0x6B /* F14 */, modifierFlags: 0x1B00)
private let testHotkeyC = Hotkey(keyCode: 0x71 /* F15 */, modifierFlags: 0x1B00)

@Suite(.serialized)
struct GlobalHotkeyRegistryTests {
    @Test func unregisteringRemovesTheHandlerSoItIsNoLongerInvoked() {
        let registry = GlobalHotkeyRegistry.shared
        var callCount = 0
        #expect(registry.register(testHotkeyA) { callCount += 1 })
        registry.simulateHotkeyPressed(testHotkeyA)
        #expect(callCount == 1)

        registry.unregister(testHotkeyA)
        registry.simulateHotkeyPressed(testHotkeyA)
        #expect(callCount == 1)
    }

    @Test func unregisteringAnUnregisteredComboIsASafeNoOp() {
        let registry = GlobalHotkeyRegistry.shared
        registry.unregister(testHotkeyB)  // must not crash

        var callCount = 0
        #expect(registry.register(testHotkeyB) { callCount += 1 })
        registry.simulateHotkeyPressed(testHotkeyB)
        #expect(callCount == 1)

        registry.unregister(testHotkeyB)
        registry.unregister(testHotkeyB)  // second unregister of the same combo: still a no-op
    }

    @Test func registeringAnAlreadyRegisteredComboReplacesTheHandlerAndFullyReleasesTheOldOne() {
        let registry = GlobalHotkeyRegistry.shared
        var firstCallCount = 0
        var secondCallCount = 0
        #expect(registry.register(testHotkeyC) { firstCallCount += 1 })

        #expect(registry.register(testHotkeyC) { secondCallCount += 1 })
        registry.simulateHotkeyPressed(testHotkeyC)

        #expect(firstCallCount == 0)
        #expect(secondCallCount == 1)

        // A single unregister must release the *replacement* registration cleanly — regression
        // test for the old registration's Carbon ref/handler ever being orphaned unreachably.
        registry.unregister(testHotkeyC)
        registry.simulateHotkeyPressed(testHotkeyC)
        #expect(secondCallCount == 1)
    }
}
