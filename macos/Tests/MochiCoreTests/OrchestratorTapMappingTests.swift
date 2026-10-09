import Foundation
import Testing

@testable import MochiCore

/// Hotkey Forwarding mappings triggered by a tap or a double tap (#92, ADR-0022), observed at the
/// `Orchestrator` seam: they are heard by the same listen-only input as 视频控制 — never
/// registered with Carbon — and forward their page keystroke only in Ghost Mode.
@Suite struct OrchestratorTapMappingTests {
    private static let space = Hotkey(keyCode: 0x31, modifierFlags: 0)

    private func started(_ fake: FakePlatformOps, config: WidgetConfig, inGhostMode: Bool = true) -> Orchestrator {
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        if inGhostMode { fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode) }
        return orchestrator
    }

    /// On `tapsOnlyVideoKeys`, so no default double tap stands in a mapping's way.
    private static func mapping(_ trigger: TriggerKey) -> WidgetConfig {
        var config = WidgetConfig.tapsOnlyVideoKeys
        config.hotkeyMappings = [HotkeyMapping(trigger: trigger, pageKeystroke: space)]
        return config
    }

    @Test func tappingAMappingsTriggerInGhostModeForwardsItsPageKey() {
        let fake = FakePlatformOps()
        let orchestrator = started(fake, config: Self.mapping(.modifierTap(.leftControl)))

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftControl, at: 10)
        }

        #expect(fake.forwardedKeystrokes == [Self.space])
    }

    @Test func doubleTappingAMappingsTriggerForwardsItsPageKey() {
        let fake = FakePlatformOps()
        let orchestrator = started(fake, config: Self.mapping(.modifierDoubleTap(.rightControl)))

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightControl, at: 10, holdFor: 0.05)
            fake.simulateModifierTap(.rightControl, at: 10.2, holdFor: 0.05)
        }

        #expect(fake.forwardedKeystrokes == [Self.space])
    }

    @Test func inNormalModeATapMappingIsNeitherHeardNorForwarded() {
        let fake = FakePlatformOps()
        let config = Self.mapping(.modifierTap(.leftControl))
        let orchestrator = started(fake, config: config, inGhostMode: false)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftControl, at: 10)
        }

        #expect(fake.startObservingInputCallCount == 0)
        #expect(fake.forwardedKeystrokes.isEmpty)
    }

    /// With every video key cleared, a tap mapping is still something to listen for.
    @Test func aTapMappingAloneIsEnoughToListenInGhostMode() {
        let fake = FakePlatformOps()
        let config = VideoControlAction.allCases.reduce(Self.mapping(.modifierTap(.leftControl))) { config, action in
            config.updatingVideoControlTrigger(nil as TriggerKey?, for: action)
        }
        let orchestrator = started(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftControl, at: 10)
        }

        #expect(fake.startObservingInputCallCount == 1)
        #expect(fake.forwardedKeystrokes == [Self.space])
    }

    @Test func aTapMappingIsNeverRegisteredWithTheSystem() {
        let fake = FakePlatformOps()
        let orchestrator = started(fake, config: Self.mapping(.modifierTap(.leftControl)), inGhostMode: false)

        withExtendedLifetime(orchestrator) {}

        #expect(Set(fake.registeredHotkeys) == [DefaultHotkeys.toggleGhostMode, DefaultHotkeys.hideWidget])
    }

    /// Right ⌥'s tap is 播放/暂停 (the default) and its double tap a mapping: the tap waits out
    /// the interval across the two features just as it does within 视频控制.
    @Test func aKeyBoundBothWaysAcrossVideoAndAMappingHoldsItsTapBack() {
        let fake = FakePlatformOps()
        let orchestrator = started(fake, config: Self.mapping(.modifierDoubleTap(.rightOption)))

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption, at: 10)
            #expect(fake.videoCommands.isEmpty)
            fake.runScheduledWork()
            fake.simulateModifierTap(.rightOption, at: 20, holdFor: 0.05)
            fake.simulateModifierTap(.rightOption, at: 20.2, holdFor: 0.05)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.map(\.command) == [.togglePlayback])
        #expect(fake.forwardedKeystrokes == [Self.space])
    }

    /// A combo mapping goes through Carbon as before; hearing its keyDown must not forward twice.
    @Test func aComboMappingIsStillForwardedOnlyThroughItsRegisteredHotkey() {
        let fake = FakePlatformOps()
        let combo = Hotkey(keyCode: 0x26, modifierFlags: 0x1000)
        let orchestrator = started(fake, config: Self.mapping(.keystroke(combo)))

        withExtendedLifetime(orchestrator) {
            fake.simulateInput(.keyDown(keyCode: combo.keyCode, modifierFlags: combo.modifierFlags, isRepeat: false, timestamp: 10))
            #expect(fake.forwardedKeystrokes.isEmpty)
            fake.simulateHotkeyPressed(combo)
        }

        #expect(fake.forwardedKeystrokes == [Self.space])
    }
}
