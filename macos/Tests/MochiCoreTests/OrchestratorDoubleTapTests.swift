import Foundation
import Testing

@testable import MochiCore

/// 视频控制's 连按两次 (#91, ADR-0022), observed at the `Orchestrator` seam: raw input in through
/// `FakePlatformOps`, video commands out. A tap on a key that is also bound to a double tap waits
/// for `FakePlatformOps.runScheduledWork()` — the stand-in for the double-tap interval passing.
@Suite struct OrchestratorDoubleTapTests {
    private func startedInGhostMode(_ fake: FakePlatformOps, config: WidgetConfig) -> Orchestrator {
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        return orchestrator
    }

    /// Right ⌥ both ways: its tap is 播放/暂停 (the default), its double tap 后退.
    private static let rightOptionBothWays = WidgetConfig()
        .updatingVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekBackward)

    @Test func doubleTappingABoundKeyRunsItsAction() {
        let fake = FakePlatformOps()
        let config = WidgetConfig().updatingVideoControlTrigger(.modifierDoubleTap(.leftControl), for: .seekForward)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftControl, at: 10, holdFor: 0.05)
            fake.simulateModifierTap(.leftControl, at: 10.2, holdFor: 0.05)
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: 5)])
    }

    @Test func aSingleTapOfAKeyBoundOnlyToADoubleTapDoesNothing() {
        let fake = FakePlatformOps()
        let config = WidgetConfig().updatingVideoControlTrigger(.modifierDoubleTap(.leftControl), for: .seekForward)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftControl, at: 10, holdFor: 0.05)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.isEmpty)
    }

    @Test func twoTapsTooFarApartAreNotADoubleTap() {
        let fake = FakePlatformOps()
        let config = WidgetConfig().updatingVideoControlTrigger(.modifierDoubleTap(.leftControl), for: .seekForward)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftControl, at: 10, holdFor: 0.05)
            fake.simulateModifierTap(.leftControl, at: 10.5, holdFor: 0.05)
        }

        #expect(fake.videoCommands.isEmpty)
    }

    @Test func aTapOnAKeyBoundBothWaysWaitsOutTheDoubleTapInterval() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: Self.rightOptionBothWays)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption, at: 10)
            #expect(fake.videoCommands.isEmpty)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.map(\.command) == [.togglePlayback])
    }

    @Test func aDoubleTapOnAKeyBoundBothWaysRunsOnlyTheDoubleTapAction() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: Self.rightOptionBothWays)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption, at: 10, holdFor: 0.05)
            fake.simulateModifierTap(.rightOption, at: 10.2, holdFor: 0.05)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: -5)])
    }

    /// Only the key bound both ways waits: right ⌘ is 后退's tap alone, so it acts at once.
    @Test func aTapOnAKeyBoundOneWayStillActsAtOnce() {
        let fake = FakePlatformOps()
        let config = WidgetConfig.tapsOnlyVideoKeys.updatingVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekForward)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightCommand, at: 10)
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: -5)])
    }

    /// A tap that is held back is still a tap only while nothing else joins in — the same rule
    /// a tap itself follows.
    @Test(arguments: [
        RawInputEvent.keyDown(keyCode: 0x26, modifierFlags: 0, isRepeat: false, timestamp: 10.2),
        .mouseDown(timestamp: 10.2),
        .modifierChanged(keyCode: ModifierKey.leftShift.keyCode, held: [.leftShift], lastPressAt: 1, timestamp: 10.2),
    ])
    func anythingElsePressedWhileATapWaitsCancelsIt(_ interruption: RawInputEvent) {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: Self.rightOptionBothWays)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption, at: 10)
            fake.simulateInput(interruption)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.isEmpty)
    }

    /// A key that's neither tapped nor double-tapped in any binding is nobody's business.
    @Test func aKeyWithNoTapBindingIsNeverHeldBack() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: Self.rightOptionBothWays)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.leftShift, at: 10)
        }

        #expect(fake.pendingScheduledWorkCount == 0)
    }

    // MARK: Defaults (ADR-0024)

    @Test func byDefaultDoubleTappingRightCommandSeeksBackAndRightOptionSeeksForward() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: WidgetConfig())

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightCommand, at: 10, holdFor: 0.05)
            fake.simulateModifierTap(.rightCommand, at: 10.2, holdFor: 0.05)
            fake.simulateModifierTap(.rightOption, at: 20, holdFor: 0.05)
            fake.simulateModifierTap(.rightOption, at: 20.2, holdFor: 0.05)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: -5), .seek(seconds: 5)])
    }

    /// Right ⌥ is bound both ways by default, so its tap — 播放/暂停 — waits out the interval.
    @Test func byDefaultTappingRightOptionTogglesPlaybackOnceTheIntervalPasses() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: WidgetConfig())

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption, at: 10)
            #expect(fake.videoCommands.isEmpty)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.map(\.command) == [.togglePlayback])
    }

    /// A single tap of right ⌘ is no longer bound to anything.
    @Test func byDefaultASingleTapOfRightCommandDoesNothing() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake, config: WidgetConfig())

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightCommand, at: 10)
            fake.runScheduledWork()
        }

        #expect(fake.videoCommands.isEmpty)
    }
}
