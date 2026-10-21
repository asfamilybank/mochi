import Foundation
import Testing

@testable import MochiCore

/// 隐藏时也从 Dock 和 ⌘Tab 中移除 (#152, ADR-0035): while the setting is on and the widget is
/// Hidden, Mochi leaves the Dock and ⌘Tab together. Switching too often leaves duplicate Dock icons
/// behind, so after each real switch there is a one-second cooldown; the window's own visibility
/// never waits for it.
@Suite struct OrchestratorDockPresenceTests {
    private final class ConfigStore {
        var config = WidgetConfig(url: URL(string: "https://example.com")!).updatingHidesFromDockWhileHidden(true)
    }

    private func makeFloatingWidget(hidesFromDock: Bool = true) -> (FakePlatformOps, ConfigStore, Orchestrator) {
        let fake = FakePlatformOps()
        let store = ConfigStore()
        store.config = store.config.updatingHidesFromDockWhileHidden(hidesFromDock)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { store.config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleFloatMode)
        return (fake, store, orchestrator)
    }

    @Test(arguments: [false, true])
    func goingHiddenLeavesTheDockAndComingBackReturnsOnlyWithTheSettingOn(hidesFromDock: Bool) {
        let (fake, _, orchestrator) = makeFloatingWidget(hidesFromDock: hidesFromDock)
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.runScheduledWork()
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        #expect(fake.dockAndAppSwitcherHiddenChanges == (hidesFromDock ? [true, false] : []))
    }

    @Test func turningTheSettingOffWhileHiddenBringsMochiBack() {
        let (fake, store, orchestrator) = makeFloatingWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.runScheduledWork()

        store.config = store.config.updatingHidesFromDockWhileHidden(false)
        orchestrator.reapplyConfiguration()

        #expect(fake.dockAndAppSwitcherHiddenChanges == [true, false])
    }

    @Test func turningTheSettingOnWhileHiddenTakesMochiAway() {
        let (fake, store, orchestrator) = makeFloatingWidget(hidesFromDock: false)
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        store.config = store.config.updatingHidesFromDockWhileHidden(true)
        orchestrator.reapplyConfiguration()

        #expect(fake.dockAndAppSwitcherHiddenChanges == [true])
    }

    @Test func returningToNormalModeWhileHiddenBringsMochiBack() {
        let (fake, _, orchestrator) = makeFloatingWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.runScheduledWork()

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleFloatMode)

        #expect(fake.dockAndAppSwitcherHiddenChanges == [true, false])
    }

    /// Hidden carries across Float and Ghost (#148), and so does leaving the Dock.
    @Test func switchingToGhostModeWhileHiddenStaysOutOfTheDock() {
        let (fake, _, orchestrator) = makeFloatingWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.runScheduledWork()

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(fake.dockAndAppSwitcherHiddenChanges == [true])
    }

    @Test func closingTheWidgetWhileHiddenBringsMochiBack() {
        let (fake, _, orchestrator) = makeFloatingWidget()
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.runScheduledWork()

        orchestrator.closeWidget()

        #expect(fake.dockAndAppSwitcherHiddenChanges == [true, false])
    }

    // MARK: The one-second cooldown

    /// Within the cooldown only the wanted state is noted; when it ends, Mochi switches if that
    /// differs from where it is — so back-and-forth presses that end where they started switch
    /// nothing.
    @Test(arguments: [
        (presses: 2, expected: [true, false]),
        (presses: 3, expected: [true]),
        (presses: 10, expected: [true, false]),
        (presses: 11, expected: [true]),
    ])
    func rapidPressesSwitchAtMostOncePerCooldown(_ row: (presses: Int, expected: [Bool])) {
        let (fake, _, orchestrator) = makeFloatingWidget()
        defer { withExtendedLifetime(orchestrator) {} }

        for _ in 0..<row.presses { fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget) }
        #expect(fake.dockAndAppSwitcherHiddenChanges == [true], "nothing more until the cooldown ends")
        fake.runScheduledWork()

        #expect(fake.dockAndAppSwitcherHiddenChanges == row.expected)
    }

    @Test func aSwitchAtTheCooldownsEndStartsAnotherCooldown() {
        let (fake, _, orchestrator) = makeFloatingWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.runScheduledWork()  // → back in the Dock, a new cooldown starts

        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        #expect(fake.dockAndAppSwitcherHiddenChanges == [true, false])
        fake.runScheduledWork()

        #expect(fake.dockAndAppSwitcherHiddenChanges == [true, false, true])
    }

    @Test func theWindowsVisibilityChangesOnEveryPressRegardless() {
        let (fake, _, orchestrator) = makeFloatingWidget()
        defer { withExtendedLifetime(orchestrator) {} }

        for _ in 0..<4 { fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget) }

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.8, 0.0, 0.8, 0.0, 0.8])
    }
}
