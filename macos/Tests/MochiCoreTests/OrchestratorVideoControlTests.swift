import Foundation
import Testing

@testable import MochiCore

/// 视频控制 (#74): Ghost Mode's listen-only video keys, observed at the `Orchestrator` seam — raw
/// input goes in through `FakePlatformOps`, video commands come out.
@Suite struct OrchestratorVideoControlTests {
    private func startedInGhostMode(
        _ fake: FakePlatformOps, config: WidgetConfig = WidgetConfig(url: nil)
    ) -> Orchestrator {
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        return orchestrator
    }

    @Test func tappingRightOptionInGhostModeTogglesPlayback() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption)
        }

        #expect(fake.videoCommands.map(\.command) == [.togglePlayback])
        #expect(fake.videoCommands.map(\.windowID) == [1])
    }
    @Test func normalModeNeitherListensNorTogglesPlayback() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig(url: nil) })

        withExtendedLifetime(orchestrator) {
            orchestrator.start()
            fake.simulateModifierTap(.rightOption)
        }

        #expect(fake.startObservingInputCallCount == 0)
        #expect(fake.videoCommands.isEmpty)
    }

    /// Everything that must *not* count as a tap of right ⌥, next to the one that must.
    @Test(arguments: [
        (name: "plain tap", events: TapSequence.plainTap, togglesPlayback: true),
        (name: "released just within 0.5s", events: TapSequence.heldFor(0.5), togglesPlayback: true),
        (name: "held past 0.5s", events: TapSequence.heldFor(0.51), togglesPlayback: false),
        (name: "a key pressed in between", events: TapSequence.withKeyInBetween, togglesPlayback: false),
        (name: "a mouse click in between", events: TapSequence.withMouseInBetween, togglesPlayback: false),
        (name: "left option", events: TapSequence.leftOptionTap, togglesPlayback: false),
        (name: "another modifier joined in", events: TapSequence.withSecondModifier, togglesPlayback: false),
        (name: "pressed while another modifier was held", events: TapSequence.whileOtherModifierHeld, togglesPlayback: false),
        (name: "fn pressed in between", events: TapSequence.withFnInBetween, togglesPlayback: false),
    ])
    func tapRecognition(_ scenario: (name: String, events: [RawInputEvent], togglesPlayback: Bool)) {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            scenario.events.forEach(fake.simulateInput)
        }

        #expect(fake.videoCommands.map(\.command) == (scenario.togglesPlayback ? [.togglePlayback] : []), "\(scenario.name)")
    }

    @Test func eachSuccessiveTapTogglesAgain() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightOption, at: 100)
            fake.simulateModifierTap(.rightOption, at: 101)
        }

        #expect(fake.videoCommands.map(\.command) == [.togglePlayback, .togglePlayback])
    }

    @Test func stillWorksWhileHidden() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
            fake.simulateModifierTap(.rightOption)
        }

        #expect(fake.videoCommands.map(\.command) == [.togglePlayback])
    }

    // MARK: Seeking (#77)

    @Test func tappingRightCommandSeeksBackFiveSeconds() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightCommand)
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: -5)])
    }

    @Test func outOfTheBoxOnlyRightOptionAndRightCommandDoAnything() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            for (index, key) in ModifierKey.allCases.enumerated() {
                fake.simulateModifierTap(key, at: 100 + Double(index))
            }
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: -5), .togglePlayback])
    }

    @Test func seekingForwardWorksOnceTheUserBindsIt() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: nil).updatingVideoControlTrigger(.modifierTap(.rightShift), for: .seekForward)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateModifierTap(.rightShift)
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: 5)])
    }

    // MARK: Ordinary keys and live config (#78)

    private static let backtick = Hotkey(keyCode: 0x32, modifierFlags: 0)
    private static let optionJ = Hotkey(keyCode: 0x26, modifierFlags: 0x0800)

    private static func keyDown(_ hotkey: Hotkey, isRepeat: Bool = false, at time: TimeInterval = 100) -> RawInputEvent {
        .keyDown(keyCode: hotkey.keyCode, modifierFlags: hotkey.modifierFlags, isRepeat: isRepeat, timestamp: time)
    }

    /// A keystroke binding fires on key-down, only with exactly the bound modifiers, and once per
    /// physical press however long the key is held.
    @Test(arguments: [
        (name: "the bound key", event: keyDown(backtick), togglesPlayback: true),
        (name: "with shift (types ~)", event: keyDown(Hotkey(keyCode: 0x32, modifierFlags: 0x0200)), togglesPlayback: false),
        (name: "auto-repeat", event: keyDown(backtick, isRepeat: true), togglesPlayback: false),
        (name: "another key", event: keyDown(Hotkey(keyCode: 0x12, modifierFlags: 0)), togglesPlayback: false),
    ])
    func keystrokeBinding(_ scenario: (name: String, event: RawInputEvent, togglesPlayback: Bool)) {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: nil).updatingVideoControlTrigger(.keystroke(Self.backtick), for: .togglePlayback)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateInput(scenario.event)
        }

        #expect(fake.videoCommands.map(\.command) == (scenario.togglesPlayback ? [.togglePlayback] : []), "\(scenario.name)")
    }

    @Test func aComboBindingNeedsItsModifiersExactly() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: nil).updatingVideoControlTrigger(.keystroke(Self.optionJ), for: .seekForward)
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {
            fake.simulateInput(Self.keyDown(Hotkey(keyCode: 0x26, modifierFlags: 0x0800 | 0x0100)))
            fake.simulateInput(Self.keyDown(Self.optionJ))
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: 5)])
    }

    @Test func eachPressIsResolvedAgainstTheConfigAtThatMoment() {
        let fake = FakePlatformOps()
        let store = VideoConfigStore()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { store.config })

        withExtendedLifetime(orchestrator) {
            orchestrator.start()
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
            fake.simulateModifierTap(.rightCommand, at: 100)
            store.config = store.config
                .updatingVideoSeekStep(10)
                .updatingVideoControlTrigger(.modifierTap(.leftCommand), for: .seekBackward)
            fake.simulateModifierTap(.rightCommand, at: 101)
            fake.simulateModifierTap(.leftCommand, at: 102)
        }

        #expect(fake.videoCommands.map(\.command) == [.seek(seconds: -5), .seek(seconds: -10)])
    }

    // MARK: When to listen

    @Test func listensFromEnteringGhostModeUntilLeavingIt() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            #expect(fake.isObservingInput)
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
            #expect(!fake.isObservingInput)
            fake.simulateModifierTap(.rightOption)
        }

        #expect(fake.startObservingInputCallCount == 1)
        #expect(fake.stopObservingInputCallCount == 1)
        #expect(fake.videoCommands.isEmpty)
    }

    @Test func closingTheWidgetInGhostModeStopsListening() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateWindowWillClose()
        }

        #expect(!fake.isObservingInput)
        #expect(fake.stopObservingInputCallCount == 1)
    }

    @Test func withNothingBoundGhostModeNeitherListensNorAsksForAccessibility() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = false
        let config = VideoControlAction.allCases.reduce(WidgetConfig(url: nil)) {
            $0.updatingVideoControlTrigger(nil, for: $1)
        }
        let orchestrator = startedInGhostMode(fake, config: config)

        withExtendedLifetime(orchestrator) {}

        #expect(fake.startObservingInputCallCount == 0)
        #expect(fake.accessibilityPermissionRequestCount == 0)
    }

    @Test func clearingTheLastBindingInGhostModeStopsListeningAndBindingOneStartsAgain() {
        let fake = FakePlatformOps()
        let store = VideoConfigStore()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { store.config })

        withExtendedLifetime(orchestrator) {
            orchestrator.start()
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
            store.config = VideoControlAction.allCases.reduce(store.config) {
                $0.updatingVideoControlTrigger(nil, for: $1)
            }
            orchestrator.reapplyConfiguration()
            #expect(!fake.isObservingInput)

            store.config = store.config.updatingVideoControlTrigger(.modifierTap(.rightOption), for: .togglePlayback)
            orchestrator.reapplyConfiguration()
            #expect(fake.isObservingInput)
        }

        #expect(fake.startObservingInputCallCount == 2)
        #expect(fake.stopObservingInputCallCount == 1)
    }

    @Test func reapplyingConfigurationInNormalModeNeverStartsListening() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig(url: nil) })

        withExtendedLifetime(orchestrator) {
            orchestrator.start()
            orchestrator.reapplyConfiguration()
        }

        #expect(fake.startObservingInputCallCount == 0)
    }

    @Test func togglingHiddenNeitherStartsNorStopsListening() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
            fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        }

        #expect(fake.startObservingInputCallCount == 1)
        #expect(fake.stopObservingInputCallCount == 0)
    }

    // MARK: Accessibility

    @Test func asksForAccessibilityOnceWithoutAnAlertAndStillEntersGhostMode() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = false
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        }

        #expect(fake.accessibilityPermissionRequestCount == 1)
        #expect(fake.presentedAlerts.isEmpty)
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false, true])
    }

    @Test func asksForAccessibilityOnlyOncePerLaunchEvenAcrossAWidgetReopen() {
        let fake = FakePlatformOps()
        fake.stubbedAccessibilityTrusted = false
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {
            fake.simulateWindowWillClose()
            orchestrator.openWidget()
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        }

        #expect(fake.accessibilityPermissionRequestCount == 1)
        #expect(fake.isObservingInput)
    }

    @Test func doesNotAskForAccessibilityWhenAlreadyTrusted() {
        let fake = FakePlatformOps()
        let orchestrator = startedInGhostMode(fake)

        withExtendedLifetime(orchestrator) {}

        #expect(fake.accessibilityPermissionRequestCount == 0)
    }
}

/// Stands in for `AppDelegate`'s live config, so a test can change it between two key presses.
private final class VideoConfigStore {
    var config = WidgetConfig(url: nil)
}

/// Raw event sequences for the tap-recognition table. Times are seconds, as `NSEvent.timestamp`.
enum TapSequence {
    private static func down(_ key: ModifierKey, held: Set<ModifierKey>? = nil, at time: TimeInterval) -> RawInputEvent {
        .modifierChanged(keyCode: key.keyCode, held: held ?? [key], timestamp: time)
    }

    private static func up(_ key: ModifierKey, stillHeld: Set<ModifierKey> = [], at time: TimeInterval) -> RawInputEvent {
        .modifierChanged(keyCode: key.keyCode, held: stillHeld, timestamp: time)
    }

    static let plainTap = heldFor(0.1)

    static func heldFor(_ duration: TimeInterval) -> [RawInputEvent] {
        [down(.rightOption, at: 10), up(.rightOption, at: 10 + duration)]
    }

    /// Right ⌥ + E — typing an accented character, not a tap.
    static let withKeyInBetween: [RawInputEvent] = [
        down(.rightOption, at: 10),
        .keyDown(keyCode: 0x0E, modifierFlags: 0x0800, isRepeat: false, timestamp: 10.05),
        up(.rightOption, at: 10.1),
    ]

    static let withMouseInBetween: [RawInputEvent] = [
        down(.rightOption, at: 10), .mouseDown(timestamp: 10.05), up(.rightOption, at: 10.1),
    ]

    static let leftOptionTap: [RawInputEvent] = [down(.leftOption, at: 10), up(.leftOption, at: 10.1)]

    /// Right ⌥ down, right ⌘ down, both released — a chord, not a tap of either.
    static let withSecondModifier: [RawInputEvent] = [
        down(.rightOption, at: 10),
        down(.rightCommand, held: [.rightOption, .rightCommand], at: 10.02),
        up(.rightCommand, stillHeld: [.rightOption], at: 10.05),
        up(.rightOption, at: 10.1),
    ]

    /// Left ⌘ already held when right ⌥ goes down and up.
    static let whileOtherModifierHeld: [RawInputEvent] = [
        down(.leftCommand, at: 9.9),
        down(.rightOption, held: [.leftCommand, .rightOption], at: 10),
        up(.rightOption, stillHeld: [.leftCommand], at: 10.1),
    ]

    /// fn (`kVK_Function`) is a modifier-type key no `ModifierKey` names.
    static let withFnInBetween: [RawInputEvent] = [
        down(.rightOption, at: 10),
        .modifierChanged(keyCode: 0x3F, held: [.rightOption], timestamp: 10.05),
        up(.rightOption, at: 10.1),
    ]
}
