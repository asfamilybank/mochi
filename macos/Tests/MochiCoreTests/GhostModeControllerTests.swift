import Foundation
import Testing

@testable import MochiCore

/// Stands in for `AppDelegate`'s live `currentConfig` — mutable from the test so the "read at
/// the point of use, never cached" rule (#46) can be pinned down by changing a value *after* the
/// controller was constructed.
private final class ConfigStore {
    var config: WidgetConfig
    init(ghostOpacity: Double, isMouseAvoidanceEnabled: Bool) {
        config = WidgetConfig(ghostOpacity: ghostOpacity, isMouseAvoidanceEnabled: isMouseAvoidanceEnabled)
    }
}

@Suite struct GhostModeControllerTests {
    private func makeSUT(
        ghostOpacity: Double = 0.2, isMouseAvoidanceEnabled: Bool = true
    ) -> (FakePlatformOps, ConfigStore, GhostModeController) {
        let fake = FakePlatformOps()
        let store = ConfigStore(ghostOpacity: ghostOpacity, isMouseAvoidanceEnabled: isMouseAvoidanceEnabled)
        let window = fake.createWidgetWindow(initialFrame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        let controller = GhostModeController(platformOps: fake, window: window, currentConfig: { store.config })
        return (fake, store, controller)
    }

    /// The whole of Ghost Mode's visibility, as one value the controller computes and hands to
    /// `setContentOpacity` (ADR-0012). Driven as a table because it *is* a truth table: nothing
    /// else about the controller decides how visible the window is.
    @Test(arguments: [
        (ghost: true, hidden: false, avoidance: false, mouseInside: false, expected: 0.2),
        (ghost: true, hidden: false, avoidance: false, mouseInside: true, expected: 0.2),
        (ghost: true, hidden: false, avoidance: true, mouseInside: false, expected: 0.2),
        (ghost: true, hidden: false, avoidance: true, mouseInside: true, expected: 0.0),
        (ghost: true, hidden: true, avoidance: false, mouseInside: false, expected: 0.0),
        (ghost: true, hidden: true, avoidance: false, mouseInside: true, expected: 0.0),
        (ghost: true, hidden: true, avoidance: true, mouseInside: false, expected: 0.0),
        (ghost: true, hidden: true, avoidance: true, mouseInside: true, expected: 0.0),
        // Normal Mode has no visibility concept of its own, so none of the other three
        // dimensions may produce a single call — `nil` here means "the platform never heard
        // about any of this", not "it was told an unchanged value".
        (ghost: false, hidden: false, avoidance: false, mouseInside: false, expected: nil),
        (ghost: false, hidden: false, avoidance: false, mouseInside: true, expected: nil),
        (ghost: false, hidden: false, avoidance: true, mouseInside: false, expected: nil),
        (ghost: false, hidden: false, avoidance: true, mouseInside: true, expected: nil),
        (ghost: false, hidden: true, avoidance: false, mouseInside: false, expected: nil),
        (ghost: false, hidden: true, avoidance: false, mouseInside: true, expected: nil),
        (ghost: false, hidden: true, avoidance: true, mouseInside: false, expected: nil),
        (ghost: false, hidden: true, avoidance: true, mouseInside: true, expected: nil),
    ])
    func effectiveOpacity(
        _ testCase: (ghost: Bool, hidden: Bool, avoidance: Bool, mouseInside: Bool, expected: Double?)
    ) {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2, isMouseAvoidanceEnabled: testCase.avoidance)

        if testCase.ghost {
            controller.toggle()
        }
        if testCase.hidden {
            controller.toggleHidden()
        }
        if testCase.mouseInside {
            fake.simulateMouseInsideChanged(true)
        }

        #expect(fake.contentOpacityChanges.last?.opacity == testCase.expected)
    }

    @Test func theMouseLeavingRestoresTheTargetOpacityRightAway() {
        // Avoidance is a courtesy, not a hiding mechanism (ADR-0012) — the widget is in the way,
        // so it steps aside, and steps back the moment it isn't.
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()

        fake.simulateMouseInsideChanged(true)
        fake.simulateMouseInsideChanged(false)

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.2])
    }

    @Test func theMouseNeverChangesOpacityWhileAvoidanceIsOff() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2, isMouseAvoidanceEnabled: false)
        controller.toggle()

        fake.simulateMouseInsideChanged(true)
        fake.simulateMouseInsideChanged(false)

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2])
    }

    @Test func theMouseNeverChangesOpacityInNormalMode() {
        let (fake, _, _) = makeSUT()

        fake.simulateMouseInsideChanged(true)
        fake.simulateMouseInsideChanged(false)

        #expect(fake.contentOpacityChanges.isEmpty)
    }

    @Test func theMouseLeavingDoesNotUndoTheHiddenHotkey() {
        // The two are bookkept separately: a window hidden on purpose must not reappear just
        // because the cursor wandered off it.
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        controller.toggleHidden()

        fake.simulateMouseInsideChanged(true)
        fake.simulateMouseInsideChanged(false)

        #expect(fake.contentOpacityChanges.last?.opacity == 0.0)
    }

    // #46: config is read when needed, never captured at construction.

    @Test func turningAvoidanceOffWhileTheMouseIsInsideRestoresVisibilityOnReapply() {
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        fake.simulateMouseInsideChanged(true)

        store.config.isMouseAvoidanceEnabled = false
        controller.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.2])
    }

    @Test func turningAvoidanceOnWhileTheMouseIsInsideStepsAsideOnReapply() {
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2, isMouseAvoidanceEnabled: false)
        controller.toggle()
        fake.simulateMouseInsideChanged(true)

        store.config.isMouseAvoidanceEnabled = true
        controller.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0])
    }

    @Test func avoidanceIsReadAtTheNextMouseCrossingWithoutAnyReapply() {
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        store.config.isMouseAvoidanceEnabled = false

        fake.simulateMouseInsideChanged(true)

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2])
    }

    @Test func entersGhostModeAtTheOpacityConfiguredAtThatMomentNotAtConstruction() {
        // The single most important #46 assertion: this fails the moment someone captures
        // `ghostOpacity` in `init` again.
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        store.config.ghostOpacity = 0.5

        controller.toggle()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.5])
    }

    @Test func reapplyConfigurationPushesANewOpacityDownWhileInGhostMode() {
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        store.config.ghostOpacity = 0.7

        controller.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.7])
    }

    @Test func reapplyConfigurationInNormalModeNeverTouchesOpacity() {
        // Not "called with 1.0" — Normal Mode is opaque regardless of any setting, so the platform
        // must not hear about the change at all.
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        store.config.ghostOpacity = 0.7

        controller.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.isEmpty)
    }

    @Test func reapplyConfigurationWhileHiddenKeepsTheWindowHidden() {
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        controller.toggleHidden()
        store.config.ghostOpacity = 0.7

        controller.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.0])
    }

    @Test func pressingHiddenInNormalModeIsASilentNoOp() {
        // Not "called with an unchanged value" — Normal Mode is a plain window with no bespoke
        // visibility concept at all, so the platform layer must never hear about this press.
        let (fake, _, controller) = makeSUT()

        controller.toggleHidden()

        #expect(fake.contentOpacityChanges.isEmpty)
    }

    @Test func pressingHiddenTwiceInGhostModeRestoresTheTargetOpacity() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()

        controller.toggleHidden()
        controller.toggleHidden()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.2])
    }

    @Test func leavingGhostModeClearsHiddenSoTheNextEntryIsVisible() {
        // Otherwise "come back to normal" would leave an invisible Normal Mode window behind,
        // and re-entering Ghost Mode would start out already hidden.
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        controller.toggleHidden()

        controller.toggle()
        controller.toggle()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 1.0, 0.2])
    }

    @Test func leavingGhostModeFrontsAndActivatesTheWindow() {
        // The one moment the user explicitly asked to interact with the widget — and the only
        // moment it is allowed to take focus (ADR-0012).
        let (fake, _, controller) = makeSUT()
        controller.toggle()

        controller.toggle()

        #expect(fake.shownWindowIDs == [1])
    }

    @Test func enteringGhostModeNeverFrontsTheWindow() {
        let (fake, _, controller) = makeSUT()

        controller.toggle()

        #expect(fake.shownWindowIDs.isEmpty)
    }

    @Test func startsInNormalMode() {
        let (_, _, controller) = makeSUT()
        #expect(controller.mode == .normal)
    }

    @Test func togglingFromNormalEntersGhostModeThroughAllBundledBehaviors() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)

        controller.toggle()

        #expect(controller.mode == .ghost)
        #expect(fake.nativeChromeVisibilityChanges.map(\.visible) == [false])
        #expect(fake.toolbarVisibilityChanges.map(\.visible) == [false])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.pinnedChanges.map(\.pinned) == [true])
    }

    @Test func togglingAgainExitsGhostModeAndRestoresEverything() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)

        controller.toggle()
        controller.toggle()

        #expect(controller.mode == .normal)
        #expect(fake.nativeChromeVisibilityChanges.map(\.visible) == [false, true])
        #expect(fake.toolbarVisibilityChanges.map(\.visible) == [false, true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
    }

    @Test func enteringGhostModeFloatsTheWindowAboveOthersAndLeavingStopsIt() {
        // Pin is internal to Ghost Mode (ADR-0012) — "float above other windows" only means
        // anything while invisibly overlaying them, so the state machine is its only driver.
        let (fake, _, controller) = makeSUT()

        controller.toggle()
        controller.toggle()

        #expect(fake.pinnedChanges.map(\.pinned) == [true, false])
        #expect(fake.pinnedChanges.map(\.windowID) == [1, 1])
    }

    @Test func exitGhostModeDropsBackToTheNormalWindowLevelLikeToggling() {
        let (fake, _, controller) = makeSUT()
        controller.toggle()

        controller.exitGhostMode()

        #expect(fake.pinnedChanges.map(\.pinned) == [true, false])
    }

    @Test func stayingInNormalModeNeverFloatsTheWindow() {
        let (fake, _, controller) = makeSUT()

        controller.exitGhostMode()

        #expect(fake.pinnedChanges.isEmpty)
    }

    @Test func startsFreshInNormalModeEveryTimeRegardlessOfPriorSessions() {
        // There is no persisted-mode input to this initializer at all (ADR-0006: restart always
        // returns to Normal Mode) — a fresh instance is definitionally in `.normal`.
        let (_, _, controller) = makeSUT()
        #expect(controller.mode == .normal)
    }

    @Test func exitGhostModeWhenAlreadyNormalDoesNothing() {
        // The tray icon's "Exit Ghost Mode" entry (#9) must be safe to invoke unconditionally,
        // without accidentally toggling back into Ghost Mode.
        let (fake, _, controller) = makeSUT()

        controller.exitGhostMode()

        #expect(controller.mode == .normal)
        #expect(fake.nativeChromeVisibilityChanges.isEmpty)
        #expect(fake.contentOpacityChanges.isEmpty)
        #expect(fake.mousePassthroughChanges.isEmpty)
    }

    @Test func exitGhostModeWhenInGhostModeRestoresEverythingLikeToggling() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()

        controller.exitGhostMode()

        #expect(controller.mode == .normal)
        #expect(fake.nativeChromeVisibilityChanges.map(\.visible) == [false, true])
        #expect(fake.toolbarVisibilityChanges.map(\.visible) == [false, true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
    }

    @Test func exitGhostModeRestoresVisibilityEvenWhileHidden() {
        // The defining scenario for #9: the window is fully invisible + click-through, and the
        // tray is the only remaining way back — it must still bring the window back.
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggle()
        controller.toggleHidden()

        controller.exitGhostMode()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 1.0])
    }
}
