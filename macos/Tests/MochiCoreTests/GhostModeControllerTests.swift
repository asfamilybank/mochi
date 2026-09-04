import Foundation
import Testing

@testable import MochiCore

@Suite struct GhostModeControllerTests {
    private func makeSUT(ghostOpacity: Double = 0.2) -> (FakePlatformOps, WidgetWindowHandle, GhostModeController) {
        let fake = FakePlatformOps()
        let window = fake.createWidgetWindow(initialFrame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        let controller = GhostModeController(platformOps: fake, window: window, ghostOpacity: ghostOpacity)
        return (fake, window, controller)
    }

    @Test func startsInNormalMode() {
        let (_, _, controller) = makeSUT()
        #expect(controller.mode == .normal)
    }

    @Test func togglingFromNormalEntersGhostModeThroughAllFourBundledBehaviors() {
        let (fake, _, controller) = makeSUT(ghostOpacity: 0.2)

        controller.toggle()

        #expect(controller.mode == .ghost)
        #expect(fake.nativeChromeVisibilityChanges.map(\.visible) == [false])
        #expect(fake.toolbarVisibilityChanges.map(\.visible) == [false])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
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

    @Test func mouseEnteringWhileInGhostModeHidesTheWindow() {
        let (fake, _, controller) = makeSUT()
        controller.toggle()

        fake.simulateMouseEntered()

        #expect(fake.windowHiddenChanges.map(\.hidden) == [true])
    }

    @Test func mouseEnteringWhileInNormalModeDoesNothing() {
        let (fake, _, _) = makeSUT()

        fake.simulateMouseEntered()

        #expect(fake.windowHiddenChanges.isEmpty)
    }

    @Test func mouseLeavingDoesNotAutomaticallyRestoreTheWindow() {
        // No `onMouseExited`/similar is wired at all — the domain doc is explicit that leaving
        // the area does not restore visibility, only toggling Ghost Mode off does.
        let (fake, _, controller) = makeSUT()
        controller.toggle()
        fake.simulateMouseEntered()

        #expect(fake.windowHiddenChanges.map(\.hidden) == [true])
        #expect(fake.windowHiddenChanges.map(\.windowID) == [1])
    }

    @Test func exitingGhostModeAfterBeingHiddenByMouseEntryUnhidesTheWindow() {
        let (fake, _, controller) = makeSUT()
        controller.toggle()
        fake.simulateMouseEntered()

        controller.toggle()

        #expect(fake.windowHiddenChanges.map(\.hidden) == [true, false])
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

    @Test func exitGhostModeUnhidesTheWindowEvenAfterBeingHiddenByMouseEntry() {
        // The defining scenario for #9: the window is fully invisible + click-through, and the
        // tray is the only remaining way back — it must still unhide the window.
        let (fake, _, controller) = makeSUT()
        controller.toggle()
        fake.simulateMouseEntered()

        controller.exitGhostMode()

        #expect(fake.windowHiddenChanges.map(\.hidden) == [true, false])
    }
}
