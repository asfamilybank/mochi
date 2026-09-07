import Foundation
import Testing

@testable import MochiCore

@Suite struct SettingsControllerTests {
    /// Mirrors `AppDelegate`'s own `persist(_ transform:)` helper: a single piece of state read
    /// and written back through transforms, exactly how `SettingsController` is wired in the real
    /// app — used here to prove edits go through *that* path rather than some parallel file write.
    private final class PersistedStore {
        private(set) var config: WidgetConfig
        private(set) var writeCount = 0

        init(_ config: WidgetConfig) {
            self.config = config
        }

        func persist(_ transform: (WidgetConfig) -> WidgetConfig) {
            config = transform(config)
            writeCount += 1
        }
    }

    /// Records what the controller dispatches on a hotkey press — the stand-in for
    /// `Orchestrator.handleGlobalHotkeyPressed` in the real app.
    private final class PressLog {
        private(set) var pressed: [Hotkey] = []
        func record(_ hotkey: Hotkey) { pressed.append(hotkey) }
    }

    private func makeController(
        store: PersistedStore, platformOps: PlatformOps = FakePlatformOps(),
        pressLog: PressLog = PressLog(), configDidChange: @escaping () -> Void = {}
    ) -> SettingsController {
        SettingsController(
            platformOps: platformOps, currentConfig: { store.config }, persist: store.persist,
            onGlobalHotkeyPressed: pressLog.record, configDidChange: configDidChange)
    }

    @Test func updatingStartupTargetPersistsThroughTheInjectedStore() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)

        controller.updateStartupTarget(.emptyPage)

        #expect(store.config.startupTarget == .emptyPage)
        #expect(store.writeCount == 1)
    }

    @Test func updatingGhostOpacityPersistsThroughTheInjectedStore() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)

        controller.updateGhostOpacity(0.6)

        #expect(store.config.ghostOpacity == 0.6)
    }

    /// AC: "有测试验证设置改动确实经过既有的配置持久化路径，而不是绕开它单独写文件." Unlike the
    /// other tests here (which use `PersistedStore`, an in-memory stand-in), this drives
    /// `SettingsController` through a `persist` function shaped exactly like `AppDelegate`'s own
    /// local `persist(_:)` — reading/writing a real `WidgetConfig.write(to:)`/`load(from:)` round
    /// trip against an actual file on disk — so it proves an edit reaches the real config file via
    /// the real serialization path, not just that some closure got called.
    @Test func editsRoundTripThroughTheRealConfigFileViaWidgetConfigsOwnReadWritePath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var currentConfig = WidgetConfig(url: URL(string: "https://example.com")!)
        try currentConfig.write(to: fileURL)
        func persist(_ transform: (WidgetConfig) -> WidgetConfig) {
            currentConfig = transform(currentConfig)
            try? currentConfig.write(to: fileURL)
        }
        let controller = SettingsController(platformOps: FakePlatformOps(), currentConfig: { currentConfig }, persist: persist)

        controller.updateGhostOpacity(0.42)
        controller.updateStartupTarget(.emptyPage)

        let reloaded = try WidgetConfig.load(from: fileURL)
        #expect(reloaded.ghostOpacity == 0.42)
        #expect(reloaded.startupTarget == .emptyPage)
    }

    @Test func editsApplyOnTopOfTheLatestPersistedStateRatherThanAStaleSnapshot() {
        // Regression test: `SettingsController` must re-read `currentConfig()` on every mutation,
        // not cache the config it was constructed with — otherwise a settings edit could stomp a
        // URL/window-state change `Orchestrator` persisted in the meantime.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)
        store.persist { $0.updatingURL(URL(string: "https://changed-elsewhere.com")!) }

        controller.updateGhostOpacity(0.5)

        #expect(store.config.url == URL(string: "https://changed-elsewhere.com")!)
        #expect(store.config.ghostOpacity == 0.5)
    }

    @Test func updatingCustomScriptPersistsThroughTheInjectedStore() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)

        controller.updateCustomScript("console.log(1)")

        #expect(store.config.customScript == "console.log(1)")
    }

    @Test func disablingABuiltInScriptAddsItsIDToTheDisabledSet() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)

        controller.setBuiltInScript("generic-video-focus", enabled: false)

        #expect(store.config.disabledBuiltInScriptIDs == ["generic-video-focus"])
    }

    @Test func reEnablingABuiltInScriptRemovesItsIDFromTheDisabledSet() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, disabledBuiltInScriptIDs: ["generic-video-focus"]))
        let controller = makeController(store: store)

        controller.setBuiltInScript("generic-video-focus", enabled: true)

        #expect(store.config.disabledBuiltInScriptIDs.isEmpty)
    }

    // MARK: - #14: hotkey mapping CRUD

    @Test func addingAMappingRegistersItsTriggerAndPersistsIt() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)
        let trigger = Hotkey(keyCode: 1, modifierFlags: 0)
        let pageKeystroke = Hotkey(keyCode: 2, modifierFlags: 0)

        let succeeded = controller.addHotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)

        #expect(succeeded)
        #expect(store.config.hotkeyMappings == [HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)])
        #expect(fake.registeredHotkeys == [trigger])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func addingAMappingWhoseTriggerAlreadyRegisteredWithTheOSFailsAndAlerts() {
        // Simulates the trigger already being claimed — by another app, or by one of Mochi's own
        // default hotkeys/existing mappings — all of which are already registered with the OS by
        // the time the settings panel can be open.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(
            trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(!succeeded)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func addingAMappingWhoseTriggerCollidesWithAnActionHotkeyFailsWithoutTouchingTheOS() {
        // Regression test: `RegisterEventHotKey` does not fail on an in-process duplicate — it
        // installs a second, independently-firing handler — so a collision with one of Mochi's own
        // action hotkeys must be caught before ever reaching `registerGlobalHotkey`, not by
        // trusting its return value (which would wrongly report success here).
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(trigger: DefaultHotkeys.hideWidget, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(!succeeded)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func addingAMappingWhoseTriggerCollidesWithAFixedLocalMenuShortcutFailsWithoutTouchingTheOS() {
        // Regression test: Carbon's RegisterEventHotKey has no visibility into MainMenuBuilder's
        // local NSMenuItem key equivalents, so this collision must be caught the same way as a
        // collision with a default global hotkey — not left to registration success/failure.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(
            trigger: DefaultHotkeys.reservedLocalMenuShortcuts[0], pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(!succeeded)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func addingAMappingWhoseTriggerAlreadyExistsInTheMappingTableFailsWithoutTouchingTheOS() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(trigger: existing.trigger, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(!succeeded)
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func updatingAMappingsPageKeystrokeOnlyDoesNotReRegisterTheTrigger() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateHotkeyMapping(at: 0, trigger: existing.trigger, pageKeystroke: Hotkey(keyCode: 20, modifierFlags: 0))

        #expect(succeeded)
        #expect(store.config.hotkeyMappings == [HotkeyMapping(trigger: existing.trigger, pageKeystroke: Hotkey(keyCode: 20, modifierFlags: 0))])
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func updatingAMappingsTriggerToAnActionHotkeyFailsWithoutTouchingTheOS() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateHotkeyMapping(at: 0, trigger: DefaultHotkeys.toggleGhostMode, pageKeystroke: existing.pageKeystroke)

        #expect(!succeeded)
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func updatingAMappingsTriggerRunsTheConflictCheck() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateHotkeyMapping(at: 0, trigger: Hotkey(keyCode: 5, modifierFlags: 0), pageKeystroke: existing.pageKeystroke)

        #expect(!succeeded)
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func removingAMappingDeletesItFromThePersistedConfig() {
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping]))
        let controller = makeController(store: store)

        controller.removeHotkeyMapping(at: 0)

        #expect(store.config.hotkeyMappings.isEmpty)
    }

    // MARK: - #46: mapping edits take effect live

    @Test func removingAMappingReleasesItsTriggerImmediately() {
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.removeHotkeyMapping(at: 0)

        #expect(fake.unregisteredHotkeys == [mapping.trigger])
    }

    @Test func removingAMappingAtAnInvalidIndexTouchesNothing() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.removeHotkeyMapping(at: 3)

        #expect(fake.unregisteredHotkeys.isEmpty)
        #expect(store.writeCount == 0)
    }

    @Test func addingAMappingRegistersATriggerThatDispatchesThroughTheSharedHotkeyHandler() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let pressLog = PressLog()
        let controller = makeController(store: store, platformOps: fake, pressLog: pressLog)
        let trigger = Hotkey(keyCode: 1, modifierFlags: 0)
        controller.addHotkeyMapping(trigger: trigger, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        fake.simulateHotkeyPressed(trigger)

        #expect(pressLog.pressed == [trigger])
    }

    @Test func updatingAMappingsTriggerUnregistersTheOldOneBeforeRegisteringTheNewOne() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)
        let newTrigger = Hotkey(keyCode: 5, modifierFlags: 0)

        let succeeded = controller.updateHotkeyMapping(at: 0, trigger: newTrigger, pageKeystroke: existing.pageKeystroke)

        #expect(succeeded)
        #expect(fake.unregisteredHotkeys == [existing.trigger])
        #expect(fake.registeredHotkeys == [newTrigger])
        #expect(fake.hotkeyCallOrder == [.unregister(existing.trigger), .register(newTrigger)])
        #expect(store.config.hotkeyMappings.map(\.trigger) == [newTrigger])
    }

    @Test func updatingAMappingsTriggerRollsBackWhenTheNewTriggerCannotBeRegistered() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let newTrigger = Hotkey(keyCode: 5, modifierFlags: 0)
        fake.hotkeysThatFailToRegister = [newTrigger]
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateHotkeyMapping(at: 0, trigger: newTrigger, pageKeystroke: existing.pageKeystroke)

        #expect(!succeeded)
        #expect(fake.hotkeyCallOrder == [.unregister(existing.trigger), .register(newTrigger), .register(existing.trigger)])
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func addingAMappingWhoseTriggerCannotBeRegisteredLeavesExistingMappingsUntouched() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let controller = makeController(store: store, platformOps: fake)

        controller.addHotkeyMapping(trigger: Hotkey(keyCode: 5, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.unregisteredHotkeys.isEmpty)
    }

    // MARK: - #46: window-behaviour switches and the change notification

    @Test func updatingSnapPersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateSnapEnabled(false)

        #expect(store.config.isSnapEnabled == false)
        #expect(notified == 1)
    }

    @Test func updatingMouseAvoidancePersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateMouseAvoidanceEnabled(false)

        #expect(store.config.isMouseAvoidanceEnabled == false)
        #expect(notified == 1)
    }

    @Test func everyPersistedEditFiresTheChangeNotificationExactlyOnce() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateGhostOpacity(0.4)
        controller.updateStartupTarget(.emptyPage)
        controller.updateCustomScript("x")
        controller.setBuiltInScript("generic-video-focus", enabled: false)
        controller.addHotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))
        controller.removeHotkeyMapping(at: 0)

        #expect(notified == store.writeCount)
        #expect(notified == 6)
    }

    @Test func aRejectedEditDoesNotFireTheChangeNotification() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        var notified = 0
        let controller = makeController(store: store, platformOps: fake, configDidChange: { notified += 1 })

        controller.addHotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(notified == 0)
    }

    @Test func aSnapEditReachesTheLiveWindowWhenWiredToTheOrchestrator() {
        // The end-to-end shape `AppDelegate` wires up: controller persists → notifies →
        // `Orchestrator.reapplyConfiguration` → `setSnapEnabled` on the open window.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: true))
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { store.config })
        orchestrator.start()
        let controller = makeController(store: store, platformOps: fake, configDidChange: orchestrator.reapplyConfiguration)

        controller.updateSnapEnabled(false)

        #expect(fake.snapEnabledChanges.map(\.enabled) == [true, false])
    }

    // MARK: - #45: the two action hotkeys

    private let customToggle = Hotkey(keyCode: 0x11, modifierFlags: 0x0100 | 0x0800)  // ⌥⌘T

    @Test func rebindingAnActionUnregistersTheOldComboThenRegistersTheNewOne() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(succeeded)
        #expect(fake.hotkeyCallOrder == [.unregister(DefaultHotkeys.toggleGhostMode), .register(customToggle)])
        #expect(store.config.hotkey(for: .toggleGhostMode) == customToggle)
        #expect(store.config.hotkeyOverrides == [.toggleGhostMode: customToggle])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func rebindingAnActionRegistersAComboThatDispatchesThroughTheSharedHotkeyHandler() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let pressLog = PressLog()
        let controller = makeController(store: store, platformOps: fake, pressLog: pressLog)
        controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        fake.simulateHotkeyPressed(customToggle)

        #expect(pressLog.pressed == [customToggle])
    }

    @Test func rebindingRollsBackToTheOldComboWhenTheNewOneIsHeldByAnotherApp() {
        // The one that matters most: "old released, new not claimed" must never be a state the
        // user can end up in.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        fake.hotkeysThatFailToRegister = [customToggle]
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(!succeeded)
        #expect(
            fake.hotkeyCallOrder == [
                .unregister(DefaultHotkeys.toggleGhostMode), .register(customToggle), .register(DefaultHotkeys.toggleGhostMode),
            ])
        #expect(store.config.hotkeyOverrides.isEmpty)
        #expect(store.writeCount == 0)
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func rebindingToTheComboAlreadyInEffectIsANoOp() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.toggleGhostMode, to: DefaultHotkeys.toggleGhostMode)

        #expect(succeeded)
        #expect(fake.hotkeyCallOrder.isEmpty)
        #expect(store.writeCount == 0)
    }

    @Test func rebindingAnActionToTheOtherActionsCurrentComboIsRejectedBeforeTouchingTheOS() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.toggleGhostMode, to: DefaultHotkeys.hideWidget)

        #expect(!succeeded)
        #expect(fake.hotkeyCallOrder.isEmpty)
        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func rebindingAnActionToAUserRebindingOfTheOtherActionIsRejected() {
        // Pins "read the combos in effect, not the default constants": ⌥⌘T is nobody's default.
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.hideWidget: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(!succeeded)
        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func rebindingAnActionToAMappingsTriggerIsRejected() {
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.toggleGhostMode, to: mapping.trigger)

        #expect(!succeeded)
        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func rebindingAnActionToAFixedLocalMenuShortcutIsRejected() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateActionHotkey(.hideWidget, to: DefaultHotkeys.reservedLocalMenuShortcuts[0])

        #expect(!succeeded)
        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func aMappingMayClaimAFormerDefaultOnceThatActionHasBeenRebound() {
        // Regression guard for the false positive the old "check against `DefaultHotkeys`" scheme
        // would produce: ⌥⌘G is free again once Ghost Mode's toggle lives on ⌥⌘T.
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(
            trigger: DefaultHotkeys.toggleGhostMode, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(succeeded)
        #expect(fake.registeredHotkeys == [DefaultHotkeys.toggleGhostMode])
    }

    @Test func aMappingMayNotClaimAnActionsUserRebinding() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(trigger: customToggle, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        #expect(!succeeded)
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func rebindingBackToTheDefaultDropsTheOverrideRatherThanStoringIt() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let controller = makeController(store: store)

        controller.updateActionHotkey(.toggleGhostMode, to: DefaultHotkeys.toggleGhostMode)

        #expect(store.config.hotkeyOverrides.isEmpty)
    }

    @Test func restoringDefaultsUnregistersEachCurrentComboAndRegistersItsDefault() {
        let customHide = Hotkey(keyCode: 0x0B, modifierFlags: 0x0100 | 0x0800)  // ⌥⌘B
        let store = PersistedStore(
            WidgetConfig(
                url: URL(string: "https://example.com")!,
                hotkeyOverrides: [.toggleGhostMode: customToggle, .hideWidget: customHide]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.resetActionHotkeysToDefaults()

        #expect(
            fake.hotkeyCallOrder == [
                .unregister(customToggle), .register(DefaultHotkeys.toggleGhostMode),
                .unregister(customHide), .register(DefaultHotkeys.hideWidget),
            ])
        #expect(store.config.hotkeyOverrides.isEmpty)
        #expect(store.writeCount == 1)
    }

    @Test func restoringDefaultsLeavesAnAlreadyDefaultActionAlone() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.resetActionHotkeysToDefaults()

        #expect(fake.hotkeyCallOrder == [.unregister(customToggle), .register(DefaultHotkeys.toggleGhostMode)])
    }

    @Test func restoringDefaultsKeepsAnOverrideWhoseDefaultAnotherAppNowHolds() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let fake = FakePlatformOps()
        fake.hotkeysThatFailToRegister = [DefaultHotkeys.toggleGhostMode]
        let controller = makeController(store: store, platformOps: fake)

        controller.resetActionHotkeysToDefaults()

        #expect(fake.hotkeyCallOrder == [.unregister(customToggle), .register(DefaultHotkeys.toggleGhostMode), .register(customToggle)])
        #expect(store.config.hotkeyOverrides == [.toggleGhostMode: customToggle])
        #expect(store.writeCount == 0)
        #expect(fake.presentedAlerts.count == 1)
    }
}
