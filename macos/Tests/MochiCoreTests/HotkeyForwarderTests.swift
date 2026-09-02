import Foundation
import Testing

@testable import MochiCore

@Suite struct HotkeyForwarderTests {
    private let mapping = HotkeyMapping(
        trigger: Hotkey(keyCode: 0x31, modifierFlags: 0),
        pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0)
    )

    @Test func registersEachMappingsTriggerAsAGlobalHotkey() {
        let fake = FakePlatformOps()
        _ = HotkeyForwarder(platformOps: fake, mappings: [mapping], isGhostModeActive: { true })

        #expect(fake.registeredHotkeys == [mapping.trigger])
    }

    @Test func forwardsThePageKeystrokeWhenTriggeredWhileInGhostModeAndTrusted() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = true
        // Held in a `let`, not discarded via `_` — `HotkeyForwarder`'s hotkey handler captures
        // `self` weakly, so a discarded instance would be deallocated before `simulateHotkeyPressed`
        // ever fires it, making the assertion below trivially (and misleadingly) pass.
        let forwarder = HotkeyForwarder(platformOps: fake, mappings: [mapping], isGhostModeActive: { true })

        fake.simulateHotkeyPressed()

        #expect(fake.forwardedKeystrokes == [mapping.pageKeystroke])
        #expect(fake.presentedAlerts.isEmpty)
        withExtendedLifetime(forwarder) {}
    }

    @Test func doesNothingWhenTriggeredOutsideGhostMode() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = true
        let forwarder = HotkeyForwarder(platformOps: fake, mappings: [mapping], isGhostModeActive: { false })

        fake.simulateHotkeyPressed()

        #expect(fake.forwardedKeystrokes.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
        withExtendedLifetime(forwarder) {}
    }

    @Test func requestsAccessibilityPermissionOnceOnFirstUntrustedTriggerAndAlertsEveryTime() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = false
        let forwarder = HotkeyForwarder(platformOps: fake, mappings: [mapping], isGhostModeActive: { true })

        fake.simulateHotkeyPressed()
        fake.simulateHotkeyPressed()

        #expect(fake.accessibilityPermissionRequestCount == 1)
        #expect(fake.presentedAlerts.count == 2)
        #expect(fake.forwardedKeystrokes.isEmpty)
        withExtendedLifetime(forwarder) {}
    }

    @Test func presentsAnAlertWhenATriggerHotkeyConflictsInsteadOfFailingSilently() {
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false

        _ = HotkeyForwarder(platformOps: fake, mappings: [mapping], isGhostModeActive: { true })

        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func doesNotPresentAnAlertWhenThereAreNoMappingsConfigured() {
        let fake = FakePlatformOps()

        _ = HotkeyForwarder(platformOps: fake, mappings: [], isGhostModeActive: { true })

        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func skipsRegisteringAMappingWhoseTriggerIsReservedByADefaultHotkeyAndAlertsAboutIt() {
        // Carbon's RegisterEventHotKey allows the same combo registered twice in-process, which
        // would make both handlers fire on one press instead of surfacing as a conflict — so a
        // reserved trigger must never reach `registerGlobalHotkey` at all.
        let fake = FakePlatformOps()

        _ = HotkeyForwarder(platformOps: fake, mappings: [mapping], reservedTriggers: [mapping.trigger], isGhostModeActive: { true })

        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.count == 1)
    }
}
