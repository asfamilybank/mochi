import Foundation
import Testing

@testable import MochiCore

/// Registration of mapping triggers moved to `Orchestrator` (#46) — see `OrchestratorTests` for
/// launch-time registration and press-time dispatch. What's left here is the forwarding decision
/// itself: mode gate, Accessibility onboarding, and the actual keystroke.
@Suite struct HotkeyForwarderTests {
    private let pageKeystroke = Hotkey(keyCode: 0x31, modifierFlags: 0)

    @Test func forwardsThePageKeystrokeWhileInGhostModeAndTrusted() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = true
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { true })

        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes == [pageKeystroke])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func doesNothingOutsideGhostMode() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = true
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { false })

        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func requestsAccessibilityPermissionOnceOnFirstUntrustedForwardAndAlertsEveryTime() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = false
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { true })

        forwarder.forward(pageKeystroke)
        forwarder.forward(pageKeystroke)

        #expect(fake.accessibilityPermissionRequestCount == 1)
        #expect(fake.presentedAlerts.count == 2)
        #expect(fake.forwardedKeystrokes.isEmpty)
    }

    @Test func readsTheModeAtForwardTimeNotAtConstruction() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = true
        var isGhost = false
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { isGhost })

        forwarder.forward(pageKeystroke)
        isGhost = true
        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes == [pageKeystroke])
    }
}
