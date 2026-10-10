import Foundation
import Testing

@testable import MochiCore

/// Registration of mapping triggers moved to `Orchestrator` (#46) — see `OrchestratorTests` for
/// launch-time registration and press-time dispatch. What's left here is the forwarding decision
/// itself: mode gate, the widget it goes to, and the actual keystroke.
@Suite struct HotkeyForwarderTests {
    private let pageKeystroke = Hotkey(keyCode: 0x31, modifierFlags: 0)
    private let window = FakeWidgetWindowHandle(id: 7)

    @Test func forwardsThePageKeystrokeIntoTheWidgetWhileInGhostMode() {
        let fake = FakePlatformOps()
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { true }, currentWindow: { window })

        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes == [pageKeystroke])
        #expect(fake.forwardedKeystrokeWindowIDs == [7])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func doesNothingOutsideGhostMode() {
        let fake = FakePlatformOps()
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { false }, currentWindow: { window })

        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func doesNothingWithoutAWidget() {
        let fake = FakePlatformOps()
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { true }, currentWindow: { nil })

        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes.isEmpty)
    }

    /// The keystroke is handed straight to the widget's web view (#93, ADR-0025), not posted
    /// through the system — nothing about that needs Accessibility, so its absence neither blocks
    /// the keystroke nor brings up the permission dialog or an alert.
    @Test func forwardsWithoutAccessibilityPermission() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = false
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { true }, currentWindow: { window })

        forwarder.forward(pageKeystroke)
        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes == [pageKeystroke, pageKeystroke])
        #expect(fake.accessibilityPermissionRequestCount == 0)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func readsTheModeAtForwardTimeNotAtConstruction() {
        let fake = FakePlatformOps()
        var isGhost = false
        let forwarder = HotkeyForwarder(platformOps: fake, isGhostModeActive: { isGhost }, currentWindow: { window })

        forwarder.forward(pageKeystroke)
        isGhost = true
        forwarder.forward(pageKeystroke)

        #expect(fake.forwardedKeystrokes == [pageKeystroke])
    }
}
