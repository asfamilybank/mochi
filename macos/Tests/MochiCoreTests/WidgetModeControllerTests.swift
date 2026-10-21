import Foundation
import Testing

@testable import MochiCore

/// Stands in for `AppDelegate`'s live `currentConfig` — mutable from the test so the "read at
/// the point of use, never cached" rule (#46) can be pinned down by changing a value *after* the
/// controller was constructed.
private final class ConfigStore {
    var config: WidgetConfig
    init(ghostOpacity: Double, floatOpacity: Double = WidgetConfig.defaultFloatOpacity) {
        config = WidgetConfig(ghostOpacity: ghostOpacity).updatingFloatOpacity(floatOpacity)
    }
}

@Suite struct WidgetModeControllerTests {
    private func makeSUT(
        ghostOpacity: Double = 0.2, floatOpacity: Double = 0.8
    ) -> (FakePlatformOps, ConfigStore, WidgetModeController) {
        let fake = FakePlatformOps()
        let store = ConfigStore(ghostOpacity: ghostOpacity, floatOpacity: floatOpacity)
        let window = fake.createWidgetWindow(initialFrame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        let controller = WidgetModeController(platformOps: fake, window: window, currentConfig: { store.config })
        return (fake, store, controller)
    }

    /// The whole of Ghost Mode's visibility, as one value the controller computes and hands to
    /// `setContentOpacity` (ADR-0012). Driven as a table because it *is* a truth table: nothing
    /// else about the controller decides how visible the window is.
    @Test(arguments: [
        (ghost: true, hidden: false, expected: 0.2),
        (ghost: true, hidden: true, expected: 0.0),
        // Normal Mode has no visibility concept of its own, so the Hidden hotkey may not produce
        // a single call — `nil` here means "the platform never heard about any of this", not "it
        // was told an unchanged value".
        (ghost: false, hidden: false, expected: nil),
        (ghost: false, hidden: true, expected: nil),
    ])
    func effectiveOpacity(_ testCase: (ghost: Bool, hidden: Bool, expected: Double?)) {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)

        if testCase.ghost {
            controller.toggleGhostMode()
        }
        if testCase.hidden {
            controller.toggleHidden()
        }

        #expect(fake.contentOpacityChanges.last?.opacity == testCase.expected)
    }

    // #46: config is read when needed, never captured at construction.

    @Test func entersGhostModeAtTheOpacityConfiguredAtThatMomentNotAtConstruction() {
        // The single most important #46 assertion: this fails the moment someone captures
        // `ghostOpacity` in `init` again.
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        store.config.ghostOpacity = 0.5

        controller.toggleGhostMode()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.5])
    }

    @Test func reapplyConfigurationPushesANewOpacityDownWhileInGhostMode() {
        let (fake, store, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggleGhostMode()
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
        controller.toggleGhostMode()
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
        controller.toggleGhostMode()

        controller.toggleHidden()
        controller.toggleHidden()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.2])
    }

    @Test func leavingGhostModeClearsHiddenSoTheNextEntryIsVisible() {
        // Otherwise "come back to normal" would leave an invisible Normal Mode window behind,
        // and re-entering Ghost Mode would start out already hidden.
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggleGhostMode()
        controller.toggleHidden()

        controller.toggleGhostMode()
        controller.toggleGhostMode()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 1.0, 0.2])
    }

    @Test func leavingGhostModeFrontsAndActivatesTheWindow() {
        // The one moment the user explicitly asked to interact with the widget — and the only
        // moment it is allowed to take focus (ADR-0012).
        let (fake, _, controller) = makeSUT()
        controller.toggleGhostMode()

        controller.toggleGhostMode()

        #expect(fake.shownWindowIDs == [1])
    }

    @Test func enteringGhostModeNeverFrontsTheWindow() {
        let (fake, _, controller) = makeSUT()

        controller.toggleGhostMode()

        #expect(fake.shownWindowIDs.isEmpty)
    }

    @Test func startsInNormalMode() {
        let (_, _, controller) = makeSUT()
        #expect(controller.mode == .normal)
    }

    @Test func togglingFromNormalEntersGhostModeThroughAllBundledBehaviors() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)

        controller.toggleGhostMode()

        #expect(controller.mode == .ghost)
        #expect(fake.windowChromeChanges.map(\.mode) == [.ghost])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.pinnedChanges.map(\.pinned) == [true])
    }

    @Test func togglingAgainExitsGhostModeAndRestoresEverything() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)

        controller.toggleGhostMode()
        controller.toggleGhostMode()

        #expect(controller.mode == .normal)
        #expect(fake.windowChromeChanges.map(\.mode) == [.ghost, .normal])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
    }

    @Test func enteringGhostModeFloatsTheWindowAboveOthersAndLeavingStopsIt() {
        // Pin is internal to Ghost Mode (ADR-0012) — "float above other windows" only means
        // anything while invisibly overlaying them, so the state machine is its only driver.
        let (fake, _, controller) = makeSUT()

        controller.toggleGhostMode()
        controller.toggleGhostMode()

        #expect(fake.pinnedChanges.map(\.pinned) == [true, false])
        #expect(fake.pinnedChanges.map(\.windowID) == [1, 1])
    }

    @Test func returnToNormalModeDropsBackToTheNormalWindowLevelLikeToggling() {
        let (fake, _, controller) = makeSUT()
        controller.toggleGhostMode()

        controller.returnToNormalMode()

        #expect(fake.pinnedChanges.map(\.pinned) == [true, false])
    }

    @Test func stayingInNormalModeNeverFloatsTheWindow() {
        let (fake, _, controller) = makeSUT()

        controller.returnToNormalMode()

        #expect(fake.pinnedChanges.isEmpty)
    }

    @Test func startsFreshInNormalModeEveryTimeRegardlessOfPriorSessions() {
        // There is no persisted-mode input to this initializer at all (ADR-0006: restart always
        // returns to Normal Mode) — a fresh instance is definitionally in `.normal`.
        let (_, _, controller) = makeSUT()
        #expect(controller.mode == .normal)
    }

    @Test func returnToNormalModeWhenAlreadyNormalDoesNothing() {
        // The tray icon's "Exit Ghost Mode" entry (#9) must be safe to invoke unconditionally,
        // without accidentally toggling back into Ghost Mode.
        let (fake, _, controller) = makeSUT()

        controller.returnToNormalMode()

        #expect(controller.mode == .normal)
        #expect(fake.windowChromeChanges.isEmpty)
        #expect(fake.contentOpacityChanges.isEmpty)
        #expect(fake.mousePassthroughChanges.isEmpty)
    }

    @Test func returnToNormalModeWhenInGhostModeRestoresEverythingLikeToggling() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggleGhostMode()

        controller.returnToNormalMode()

        #expect(controller.mode == .normal)
        #expect(fake.windowChromeChanges.map(\.mode) == [.ghost, .normal])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
    }

    @Test func returnToNormalModeRestoresVisibilityEvenWhileHidden() {
        // The defining scenario for #9: the window is fully invisible + click-through, and the
        // tray is the only remaining way back — it must still bring the window back.
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)
        controller.toggleGhostMode()
        controller.toggleHidden()

        controller.returnToNormalMode()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 1.0])
    }
    // MARK: Hidden pauses the page (#76, ADR-0021)

    @Test func goingHiddenPausesEveryPlayingMediaElementOnThePage() {
        let (fake, _, controller) = makeSUT()
        controller.toggleGhostMode()

        controller.toggleHidden()

        #expect(fake.mediaPausedWindowIDs == [1])
    }

    @Test func comingBackFromHiddenResumesNothing() {
        let (fake, _, controller) = makeSUT()
        controller.toggleGhostMode()
        controller.toggleHidden()

        controller.toggleHidden()

        #expect(fake.mediaPausedWindowIDs == [1])
        #expect(fake.videoCommands.isEmpty)
    }

    @Test func leavingGhostModeWhileHiddenResumesNothingEither() {
        let (fake, _, controller) = makeSUT()
        controller.toggleGhostMode()
        controller.toggleHidden()

        controller.toggleGhostMode()

        #expect(fake.mediaPausedWindowIDs == [1])
        #expect(fake.videoCommands.isEmpty)
    }

    @Test func pressingHiddenInNormalModePausesNothing() {
        let (fake, _, controller) = makeSUT()

        controller.toggleHidden()

        #expect(fake.mediaPausedWindowIDs.isEmpty)
    }

    // MARK: - Float Mode (#147, ADR-0035)

    enum Key { case float, ghost }

    /// ADR-0035's switching table: each mode's key enters that mode, or returns to Normal Mode
    /// from it; Float and Ghost switch straight into each other.
    @Test(arguments: [
        (keys: [Key.float], expected: WidgetMode.float),
        (keys: [.float, .float], expected: .normal),
        (keys: [.float, .ghost], expected: .ghost),
        (keys: [.ghost, .float], expected: .float),
        (keys: [.ghost, .ghost], expected: .normal),
        (keys: [.float, .ghost, .ghost], expected: .normal),
        (keys: [.ghost, .float, .float], expected: .normal),
    ])
    func switchingTable(_ testCase: (keys: [Key], expected: WidgetMode)) {
        let (_, _, controller) = makeSUT()

        for key in testCase.keys {
            switch key {
            case .float: controller.toggleFloatMode()
            case .ghost: controller.toggleGhostMode()
            }
        }

        #expect(controller.mode == testCase.expected)
    }

    @Test func enteringFloatModeFromNormalAppliesItsWholeBundleAndTakesFocus() {
        let (fake, _, controller) = makeSUT(floatOpacity: 0.8)

        controller.toggleFloatMode()

        #expect(fake.windowChromeChanges.map(\.mode) == [.float])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [false])
        #expect(fake.pinnedChanges.map(\.pinned) == [true])
        // An interactive mode: the window comes forward and becomes key, unlike Ghost Mode.
        #expect(fake.shownWindowIDs == [1])
        #expect(fake.deactivateAppCallCount == 0)
    }

    @Test func leavingFloatModeForNormalRestoresThePlainWindow() {
        let (fake, _, controller) = makeSUT(floatOpacity: 0.8)

        controller.toggleFloatMode()
        controller.toggleFloatMode()

        #expect(fake.windowChromeChanges.map(\.mode) == [.float, .normal])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8, 1.0])
        #expect(fake.pinnedChanges.map(\.pinned) == [true, false])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [false, false])
    }

    @Test func floatToGhostTurnsOnPassthroughAndGivesUpFocus() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2, floatOpacity: 0.8)
        controller.toggleFloatMode()

        controller.toggleGhostMode()

        #expect(fake.windowChromeChanges.map(\.mode) == [.float, .ghost])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8, 0.2])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [false, true])
        #expect(fake.pinnedChanges.last?.pinned == true)
        #expect(fake.deactivateAppCallCount == 1)
    }

    @Test func ghostToFloatTurnsOffPassthroughAndTakesFocus() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2, floatOpacity: 0.8)
        controller.toggleGhostMode()

        controller.toggleFloatMode()

        #expect(fake.windowChromeChanges.map(\.mode) == [.ghost, .float])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.8])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
        #expect(fake.pinnedChanges.last?.pinned == true)
        #expect(fake.shownWindowIDs == [1])
    }

    @Test func returnToNormalModeLeavesFloatModeToo() {
        let (fake, _, controller) = makeSUT()
        controller.toggleFloatMode()

        controller.returnToNormalMode()

        #expect(controller.mode == .normal)
        #expect(fake.windowChromeChanges.map(\.mode) == [.float, .normal])
    }

    @Test func entersFloatModeAtTheOpacityConfiguredAtThatMoment() {
        let (fake, store, controller) = makeSUT(floatOpacity: 0.8)
        store.config.floatOpacity = 0.6

        controller.toggleFloatMode()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.6])
    }

    @Test func reapplyConfigurationPushesANewOpacityDownWhileInFloatMode() {
        let (fake, store, controller) = makeSUT(floatOpacity: 0.8)
        controller.toggleFloatMode()
        store.config.floatOpacity = 0.5

        controller.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8, 0.5])
    }

    // MARK: - Hidden shared by Float and Ghost (#148, ADR-0035)

    @Test func goingHiddenInFloatModeMakesTheWindowInvisiblePausesTheMediaAndGivesUpFocus() {
        let (fake, _, controller) = makeSUT(floatOpacity: 0.8)
        controller.toggleFloatMode()

        controller.toggleHidden()

        #expect(controller.canHide)
        #expect(controller.isHidden)
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8, 0.0])
        #expect(fake.mediaPausedWindowIDs == [1])
        #expect(fake.deactivateAppCallCount == 1)
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [false, true])
    }

    @Test func comingBackFromHiddenInFloatModeOnlyShowsTheWindowAndNeverActivates() {
        let (fake, _, controller) = makeSUT(floatOpacity: 0.8)
        controller.toggleFloatMode()
        controller.toggleHidden()

        controller.toggleHidden()

        #expect(!controller.isHidden)
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8, 0.0, 0.8])
        // Shown once, on entering Float Mode: unhiding brings nothing forward.
        #expect(fake.shownWindowIDs == [1])
        #expect(fake.deactivateAppCallCount == 1)
    }

    @Test func switchingFromFloatToGhostWhileHiddenStaysHidden() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2, floatOpacity: 0.8)
        controller.toggleFloatMode()
        controller.toggleHidden()

        controller.toggleGhostMode()

        #expect(controller.mode == .ghost)
        #expect(controller.isHidden)
        #expect(fake.contentOpacityChanges.last?.opacity == 0.0)
        // Unhiding then lands on Ghost Mode's own target.
        controller.toggleHidden()
        #expect(fake.contentOpacityChanges.last?.opacity == 0.2)
    }

    @Test func switchingFromGhostToFloatWhileHiddenStaysHiddenAndDoesNotActivate() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2, floatOpacity: 0.8)
        controller.toggleGhostMode()
        controller.toggleHidden()

        controller.toggleFloatMode()

        #expect(controller.mode == .float)
        #expect(controller.isHidden)
        #expect(fake.contentOpacityChanges.last?.opacity == 0.0)
        // Still click-through while hidden: an invisible window mustn't catch a click.
        #expect(fake.mousePassthroughChanges.last?.enabled == true)
        #expect(fake.shownWindowIDs.isEmpty)
        controller.toggleHidden()
        #expect(fake.contentOpacityChanges.last?.opacity == 0.8)
        #expect(fake.mousePassthroughChanges.last?.enabled == false)
    }

    @Test func leavingFloatModeWhileHiddenClearsHiddenAndShowsTheWindow() {
        let (fake, _, controller) = makeSUT(floatOpacity: 0.8)
        controller.toggleFloatMode()
        controller.toggleHidden()

        controller.toggleFloatMode()

        #expect(controller.mode == .normal)
        #expect(!controller.isHidden)
        #expect(fake.contentOpacityChanges.last?.opacity == 1.0)
        #expect(fake.shownWindowIDs == [1, 1])
    }

    @Test func hiddenChangesAreReportedLikeModeChanges() {
        let (_, _, controller) = makeSUT()
        var changes = 0
        controller.onStateChanged = { changes += 1 }
        controller.toggleFloatMode()

        controller.toggleHidden()
        controller.toggleHidden()

        #expect(changes == 3)
    }
}
