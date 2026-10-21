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

    @Test func updatingCustomStylesheetPersistsThroughTheInjectedStore() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)

        controller.updateCustomStylesheet("body { color: red; }")

        #expect(store.config.customStylesheet == "body { color: red; }")
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
        let trigger = Hotkey(keyCode: 1, modifierFlags: 0x1000)
        let pageKeystroke = Hotkey(keyCode: 2, modifierFlags: 0x1000)

        let rejection = controller.addHotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)

        #expect(rejection == nil)
        #expect(store.config.hotkeyMappings == [HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)])
        #expect(fake.registeredHotkeys == [trigger])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func addingAMappingWhoseTriggerAlreadyRegisteredWithTheOSIsRefusedAsHeldByAnotherApp() {
        // Simulates the trigger already being claimed — by another app, or by one of Mochi's own
        // default hotkeys/existing mappings — all of which are already registered with the OS by
        // the time the settings panel can be open.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(
            trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == .heldByAnotherApp)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func addingAMappingWhoseTriggerCollidesWithAnActionHotkeyFailsWithoutTouchingTheOS() {
        // Regression test: `RegisterEventHotKey` does not fail on an in-process duplicate — it
        // installs a second, independently-firing handler — so a collision with one of Mochi's own
        // action hotkeys must be caught before ever reaching `registerGlobalHotkey`, not by
        // trusting its return value (which would wrongly report success here).
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(trigger: DefaultHotkeys.hideWidget, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == .conflictsWithAction(.hideWidget))
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func addingAMappingWhoseTriggerCollidesWithAFixedLocalMenuShortcutFailsWithoutTouchingTheOS() {
        // Regression test: Carbon's RegisterEventHotKey has no visibility into MainMenuBuilder's
        // local NSMenuItem key equivalents, so this collision must be caught the same way as a
        // collision with a default global hotkey — not left to registration success/failure.
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(
            trigger: DefaultHotkeys.reservedLocalMenuShortcuts[0], pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == .reservedMenuShortcut)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    /// #62: the App menu's 隐藏 Mochi (⌘H) and 隐藏其他 (⌥⌘H) are local menu shortcuts too, so a
    /// mapping can't claim either — ⌥⌘H in particular is the combo #58 gave back to every app.
    @Test(arguments: [Hotkey(keyCode: 0x04, modifierFlags: 0x0100), Hotkey(keyCode: 0x04, modifierFlags: 0x0900)])
    func addingAMappingOnAnAppMenuHideShortcutFails(trigger: Hotkey) {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(trigger: trigger, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == .reservedMenuShortcut)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func addingAMappingWhoseTriggerAlreadyExistsInTheMappingTableFailsWithoutTouchingTheOS() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(trigger: existing.trigger, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == .conflictsWithMapping(existing))
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func updatingAMappingsPageKeystrokeOnlyDoesNotReRegisterTheTrigger() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: existing.trigger, pageKeystroke: Hotkey(keyCode: 20, modifierFlags: 0x1000))

        #expect(rejection == nil)
        #expect(store.config.hotkeyMappings == [HotkeyMapping(trigger: existing.trigger, pageKeystroke: Hotkey(keyCode: 20, modifierFlags: 0x1000))])
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func updatingAMappingsTriggerToAnActionHotkeyFailsWithoutTouchingTheOS() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: DefaultHotkeys.toggleGhostMode, pageKeystroke: existing.pageKeystroke)

        #expect(rejection == .conflictsWithAction(.toggleGhostMode))
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func updatingAMappingsTriggerRunsTheConflictCheck() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: Hotkey(keyCode: 5, modifierFlags: 0x1000), pageKeystroke: existing.pageKeystroke)

        #expect(rejection == .heldByAnotherApp)
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func removingAMappingDeletesItFromThePersistedConfig() {
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping]))
        let controller = makeController(store: store)

        controller.removeHotkeyMapping(at: 0)

        #expect(store.config.hotkeyMappings.isEmpty)
    }

    // MARK: - #46: mapping edits take effect live

    @Test func removingAMappingReleasesItsTriggerImmediately() {
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.removeHotkeyMapping(at: 0)

        #expect(fake.unregisteredHotkeys == [mapping.registeredHotkey!])
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
        let trigger = Hotkey(keyCode: 1, modifierFlags: 0x1000)
        controller.addHotkeyMapping(trigger: trigger, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        fake.simulateHotkeyPressed(trigger)

        #expect(pressLog.pressed == [trigger])
    }

    @Test func updatingAMappingsTriggerUnregistersTheOldOneBeforeRegisteringTheNewOne() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)
        let newTrigger = Hotkey(keyCode: 5, modifierFlags: 0x1000)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: newTrigger, pageKeystroke: existing.pageKeystroke)

        #expect(rejection == nil)
        #expect(fake.unregisteredHotkeys == [existing.registeredHotkey!])
        #expect(fake.registeredHotkeys == [newTrigger])
        #expect(fake.hotkeyCallOrder == [.unregister(existing.registeredHotkey!), .register(newTrigger)])
        #expect(store.config.hotkeyMappings.map(\.registeredHotkey) == [newTrigger])
    }

    @Test func updatingAMappingsTriggerRollsBackWhenTheNewTriggerCannotBeRegistered() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let newTrigger = Hotkey(keyCode: 5, modifierFlags: 0x1000)
        fake.hotkeysThatFailToRegister = [newTrigger]
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: newTrigger, pageKeystroke: existing.pageKeystroke)

        #expect(rejection == .heldByAnotherApp)
        #expect(fake.hotkeyCallOrder == [.unregister(existing.registeredHotkey!), .register(newTrigger), .register(existing.registeredHotkey!)])
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func addingAMappingWhoseTriggerCannotBeRegisteredLeavesExistingMappingsUntouched() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let controller = makeController(store: store, platformOps: fake)

        controller.addHotkeyMapping(trigger: Hotkey(keyCode: 5, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

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

    @Test func updatingSearchEnginePersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateSearchEngine(.duckDuckGo)

        #expect(store.config.searchEngine == .duckDuckGo)
        #expect(store.config.url == URL(string: "https://example.com")!)
        #expect(notified == 1)
    }

    @Test(arguments: [
        DownloadLocation.askEachTime, .folder(URL(fileURLWithPath: "/fake/Chosen", isDirectory: true)), .downloadsFolder,
    ])
    func updatingDownloadLocationPersistsAndNotifies(_ location: DownloadLocation) {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!).updatingSearchEngine(.bing))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateDownloadLocation(location)

        #expect(store.config.downloadLocation == location)
        #expect(store.config.searchEngine == .bing)
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
        controller.addHotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))
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

        controller.addHotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

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

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(rejection == nil)
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

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(rejection == .heldByAnotherApp)
        #expect(
            fake.hotkeyCallOrder == [
                .unregister(DefaultHotkeys.toggleGhostMode), .register(customToggle), .register(DefaultHotkeys.toggleGhostMode),
            ])
        #expect(store.config.hotkeyOverrides.isEmpty)
        #expect(store.writeCount == 0)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func rebindingToTheComboAlreadyInEffectIsANoOp() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: DefaultHotkeys.toggleGhostMode)

        #expect(rejection == nil)
        #expect(fake.hotkeyCallOrder.isEmpty)
        #expect(store.writeCount == 0)
    }

    @Test func rebindingAnActionToTheOtherActionsCurrentComboIsRejectedBeforeTouchingTheOS() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: DefaultHotkeys.hideWidget)

        #expect(rejection == .conflictsWithAction(.hideWidget))
        #expect(fake.hotkeyCallOrder.isEmpty)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func rebindingAnActionToAUserRebindingOfTheOtherActionIsRejected() {
        // Pins "read the combos in effect, not the default constants": ⌥⌘T is nobody's default.
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.hideWidget: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(rejection == .conflictsWithAction(.hideWidget))
        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func rebindingAnActionToAMappingsTriggerIsRejected() {
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0x1000))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: mapping.registeredHotkey)

        #expect(rejection == .conflictsWithMapping(mapping))
        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func rebindingAnActionToAFixedLocalMenuShortcutIsRejected() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.hideWidget, to: DefaultHotkeys.reservedLocalMenuShortcuts[0])

        #expect(rejection == .reservedMenuShortcut)
        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func aMappingMayClaimAFormerDefaultOnceThatActionHasBeenRebound() {
        // Regression guard for the false positive the old "check against `DefaultHotkeys`" scheme
        // would produce: ⌥G is free again once Ghost Mode's toggle lives on ⌥⌘T.
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(
            trigger: DefaultHotkeys.toggleGhostMode, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == nil)
        #expect(fake.registeredHotkeys == [DefaultHotkeys.toggleGhostMode])
    }

    @Test func aMappingMayNotClaimAnActionsUserRebinding() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: customToggle]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(trigger: customToggle, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0x1000))

        #expect(rejection == .conflictsWithAction(.toggleGhostMode))
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

    // MARK: - #86: a refusal says why, in words the settings row can show

    @Test(arguments: [
        (reason: HotkeyRejection.conflictsWithAction(.hideWidget), message: "与「隐藏窗口」冲突"),
        (reason: .conflictsWithVideoControl(.seekBackward), message: "与视频控制「后退」冲突"),
        (reason: .conflictsWithMapping(HotkeyMapping(trigger: Hotkey(keyCode: 0x31, modifierFlags: 0x1800), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))),
         message: "与映射「⌃⌥Space → Space」冲突"),
        (reason: .reservedMenuShortcut, message: "这是 Mochi 菜单里的快捷键"),
        (reason: .heldByAnotherApp, message: "已被其他应用占用"),
    ])
    func eachRefusalReadsAsItsOwnReason(_ c: (reason: HotkeyRejection, message: String)) {
        #expect(c.reason.message == c.message)
    }

    // MARK: - #85: clearing an action hotkey

    @Test func clearingAnActionReleasesItsComboAndPersistsItAsUnbound() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.hideWidget, to: nil)

        #expect(rejection == nil)
        #expect(fake.hotkeyCallOrder == [.unregister(DefaultHotkeys.hideWidget)])
        #expect(store.config.hotkey(for: .hideWidget) == nil)
        #expect(store.config.hotkey(for: .toggleGhostMode) == DefaultHotkeys.toggleGhostMode)
    }

    @Test func recordingAComboForAClearedActionOnlyRegistersIt() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: nil]))
        let fake = FakePlatformOps()
        let pressLog = PressLog()
        let controller = makeController(store: store, platformOps: fake, pressLog: pressLog)

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)
        fake.simulateHotkeyPressed(customToggle)

        #expect(rejection == nil)
        #expect(fake.hotkeyCallOrder == [.register(customToggle)])
        #expect(store.config.hotkey(for: .toggleGhostMode) == customToggle)
        #expect(pressLog.pressed == [customToggle])
    }

    /// Nothing to roll back to — the action simply stays cleared.
    @Test func recordingAComboAnotherAppHoldsForAClearedActionLeavesItCleared() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: nil]))
        let fake = FakePlatformOps()
        fake.hotkeysThatFailToRegister = [customToggle]
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.toggleGhostMode, to: customToggle)

        #expect(rejection == .heldByAnotherApp)
        #expect(fake.hotkeyCallOrder == [.register(customToggle)])
        #expect(store.config.hotkey(for: .toggleGhostMode) == nil)
        #expect(store.writeCount == 0)
    }

    @Test func clearingAnAlreadyClearedActionTouchesNothing() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.hideWidget: nil]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        #expect(controller.updateActionHotkey(.hideWidget, to: nil) == nil)
        #expect(fake.hotkeyCallOrder.isEmpty)
        #expect(store.writeCount == 0)
    }

    @Test func restoringDefaultsRegistersAClearedActionAgain() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: nil]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.resetActionHotkeysToDefaults()

        #expect(fake.hotkeyCallOrder == [.register(DefaultHotkeys.toggleGhostMode)])
        #expect(store.config.hotkeyOverrides.isEmpty)
    }

    @Test func restoringDefaultsKeepsAClearedActionClearedWhenAnotherAppHoldsItsDefault() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: nil]))
        let fake = FakePlatformOps()
        fake.hotkeysThatFailToRegister = [DefaultHotkeys.toggleGhostMode]
        let controller = makeController(store: store, platformOps: fake)

        controller.resetActionHotkeysToDefaults()

        #expect(fake.hotkeyCallOrder == [.register(DefaultHotkeys.toggleGhostMode)])
        #expect(store.config.hotkey(for: .toggleGhostMode) == nil)
        #expect(fake.presentedAlerts.count == 1)
    }

    /// Once a cleared action's default has been taken by something that never reaches the OS —
    /// a mapping registered in-process, or a video key that only listens — restoring it would
    /// double-book the combo. It stays as it is and is listed as not restored.
    @Test(arguments: [false, true])
    func restoringDefaultsLeavesAnActionWhoseDefaultSomethingElseNowHolds(heldByVideoKey: Bool) {
        var config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: nil])
        if heldByVideoKey {
            config = config.updatingVideoControlTrigger(.keystroke(DefaultHotkeys.toggleGhostMode), for: .seekForward)
        } else {
            config = config.updatingHotkeyMappings([
                HotkeyMapping(trigger: DefaultHotkeys.toggleGhostMode, pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0x1000)),
            ])
        }
        let store = PersistedStore(config)
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.resetActionHotkeysToDefaults()

        #expect(fake.hotkeyCallOrder.isEmpty)
        #expect(store.config.hotkey(for: .toggleGhostMode) == nil)
        #expect(fake.presentedAlerts.count == 1)
    }

    /// Swapping the two actions' combos and then restoring must put both back — each one's
    /// default is held only by the other action, which is itself on its way back.
    @Test func restoringDefaultsUndoesASwapOfTheTwoActions() {
        let store = PersistedStore(
            WidgetConfig(
                url: URL(string: "https://example.com")!,
                hotkeyOverrides: [.toggleGhostMode: DefaultHotkeys.hideWidget, .hideWidget: DefaultHotkeys.toggleGhostMode]))
        let controller = makeController(store: store)

        controller.resetActionHotkeysToDefaults()

        #expect(store.config.hotkeyOverrides.isEmpty)
    }

    // #86: a refusal persists nothing and announces no change.
    @Test func aRefusedActionOrVideoKeyEditFiresNoChangeNotification() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notifications = 0
        let controller = makeController(store: store, configDidChange: { notifications += 1 })

        #expect(controller.updateActionHotkey(.toggleGhostMode, to: DefaultHotkeys.hideWidget) == .conflictsWithAction(.hideWidget))
        #expect(controller.updateVideoControlTrigger(.modifierDoubleTap(.rightCommand), for: .seekForward) == .conflictsWithVideoControl(.seekBackward))
        #expect(notifications == 0)
        #expect(store.writeCount == 0)
    }

    /// A cleared action holds no combo, so its default is free for anything else to take.
    @Test func aClearedActionsDefaultComboIsFreeForAMappingOrAVideoKey() {
        let store = PersistedStore(
            WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.hideWidget: nil]))
        let controller = makeController(store: store)

        #expect(controller.addHotkeyMapping(trigger: DefaultHotkeys.hideWidget, pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0x1000)) == nil)
        #expect(controller.updateActionHotkey(.toggleGhostMode, to: Hotkey(keyCode: 0x26, modifierFlags: 0x0800)) == nil)
        #expect(controller.updateVideoControlTrigger(.keystroke(Hotkey(keyCode: 0x26, modifierFlags: 0x1000)), for: .seekForward) == nil)
    }

    // #70

    @Test func updatingAutoplayPolicyPersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig())
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateAutoplayPolicy(.stopMediaWithSound)

        #expect(store.config.autoplayPolicy == .stopMediaWithSound)
        #expect(notified == 1)
    }

    @Test func updatingMinimumFontSizePersistsAndNotifiesAndNilClearsIt() {
        let store = PersistedStore(WidgetConfig())
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateMinimumFontSize(12)
        #expect(store.config.minimumFontSize == 12)
        controller.updateMinimumFontSize(nil)
        #expect(store.config.minimumFontSize == nil)
        #expect(notified == 2)
    }

    // MARK: - #69: 摄像头 / 麦克风

    @Test func updatingMediaCapturePermissionsPersistsEachIndependentlyAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateCameraPermission(.allow)
        #expect(store.config.cameraPermission == .allow && store.config.microphonePermission == .ask)
        controller.updateMicrophonePermission(.deny)
        #expect(store.config.cameraPermission == .allow && store.config.microphonePermission == .deny)
        #expect(store.config.url == URL(string: "https://example.com")!)
        #expect(notified == 2)
    }

    // MARK: - #72: 高级 pane

    @Test func updatingHTTPWarningPersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateHTTPWarningEnabled(true)

        #expect(store.config.isHTTPWarningEnabled == true)
        #expect(notified == 1)
    }

    @Test func updatingWebInspectorPersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updateWebInspectorEnabled(true)

        #expect(store.config.isWebInspectorEnabled == true)
        #expect(notified == 1)
    }

    // MARK: - Writes made elsewhere (#109)

    /// The settings window must see what was written outside it — the 询问框's 「访问此网站时允许」
    /// (#109), the page last visited — or its exceptions table goes stale. Wired like
    /// `AppDelegate`: one config, one `persist` shared by `Orchestrator` and the controller, which
    /// reports every write to the controller.
    @Test func aWriteMadeElsewhereReachesThePanel() {
        let fake = FakePlatformOps()
        let request = MediaCaptureRequest(device: .camera, host: "meet.example.com")
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        var controller: SettingsController?
        let persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void = { transform in
            config = transform(config)
            controller?.configWasPersisted()
        }
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, persist: persist)
        controller = SettingsController(platformOps: fake, currentConfig: { config }, persist: persist)
        var seen: [[WidgetConfig.PagePermissionException]] = []
        controller?.onConfigPersisted { seen.append(controller?.config.cameraExceptions ?? []) }

        withExtendedLifetime(orchestrator) {
            orchestrator.start()
            _ = fake.simulateMediaCaptureRequested(request)
            _ = fake.simulateMediaCapturePromptAnswered(.allowOnThisSite, to: request)
        }

        #expect(seen.last?.map(\.host) == ["meet.example.com"])
        #expect(seen.last?.map(\.setting) == [.allow])
    }

    @Test func everyHandlerHearsOfEveryWrite() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let controller = makeController(store: store)
        var heard = [0, 0]
        controller.onConfigPersisted { heard[0] += 1 }
        controller.onConfigPersisted { heard[1] += 1 }

        controller.configWasPersisted()
        controller.configWasPersisted()

        #expect(heard == [2, 2])
    }

    // MARK: - #107: 清除浏览数据…

    private static let clearingNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeClearingController(
        store: PersistedStore, platformOps: FakePlatformOps, configDidChange: @escaping () -> Void = {}
    ) -> SettingsController {
        let controller = makeController(store: store, platformOps: platformOps, configDidChange: configDidChange)
        controller.currentDate = { Self.clearingNow }
        return controller
    }

    @Test(arguments: [
        (kinds: [BrowsingDataKind.cache], categories: [WebsiteDataCategory.cache]),
        (kinds: [.websiteData], categories: [.cookiesAndOtherData]),
        (kinds: [.websiteData, .cache], categories: [.cookiesAndOtherData, .cache]),
        (kinds: [.websiteData, .cache, .pagePermissionExceptions], categories: [.cookiesAndOtherData, .cache]),
    ])
    func clearingBrowsingDataRemovesTheTickedWebsiteDataFromTheRangesStart(
        _ row: (kinds: [BrowsingDataKind], categories: [WebsiteDataCategory])
    ) {
        let fake = FakePlatformOps()
        let controller = makeClearingController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        controller.clearBrowsingData(Set(row.kinds), from: .past24Hours)

        #expect(fake.websiteDataRemovals.map(\.types) == [Set(row.categories)])
        #expect(fake.websiteDataRemovals.map(\.modifiedSince) == [Self.clearingNow.addingTimeInterval(-86_400)])
    }

    @Test func clearingAllTimeRemovesWebsiteDataFromTheDistantPast() {
        let fake = FakePlatformOps()
        let controller = makeClearingController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        controller.clearBrowsingData(BrowsingDataKind.defaultSelection, from: .allTime)

        #expect(fake.websiteDataRemovals.map(\.modifiedSince) == [.distantPast])
    }

    /// Website data isn't config: clearing only it writes nothing and notifies no one.
    @Test func clearingOnlyWebsiteDataLeavesTheConfigAlone() {
        let store = PersistedStore(Self.configWithExceptions())
        let fake = FakePlatformOps()
        var notified = 0
        let controller = makeClearingController(store: store, platformOps: fake, configDidChange: { notified += 1 })

        controller.clearBrowsingData([.websiteData, .cache], from: .allTime)

        #expect(store.writeCount == 0)
        #expect(notified == 0)
        #expect(store.config == Self.configWithExceptions())
    }

    /// Exceptions for both devices: two changed 30 minutes ago, one 2 days ago, one 30 days ago.
    private static func configWithExceptions() -> WidgetConfig {
        WidgetConfig()
            .updatingPagePermissionException(
                .camera, host: "recent.example", setting: .allow, modifiedAt: clearingNow.addingTimeInterval(-1_800))
            .updatingPagePermissionException(
                .microphone, host: "recent.example", setting: .deny, modifiedAt: clearingNow.addingTimeInterval(-1_800))
            .updatingPagePermissionException(
                .camera, host: "days.example", setting: .deny, modifiedAt: clearingNow.addingTimeInterval(-2 * 86_400))
            .updatingPagePermissionException(
                .microphone, host: "old.example", setting: .allow, modifiedAt: clearingNow.addingTimeInterval(-30 * 86_400))
    }

    @Test(arguments: [
        (range: BrowsingDataTimeRange.pastHour, camera: ["days.example"], microphone: ["old.example"]),
        (range: .past24Hours, camera: ["days.example"], microphone: ["old.example"]),
        (range: .past7Days, camera: [], microphone: ["old.example"]),
        (range: .past4Weeks, camera: [], microphone: ["old.example"]),
        (range: .allTime, camera: [], microphone: []),
    ])
    func clearingPagePermissionExceptionsRemovesThoseModifiedWithinTheRange(
        _ row: (range: BrowsingDataTimeRange, camera: [String], microphone: [String])
    ) {
        let store = PersistedStore(Self.configWithExceptions())
        var notified = 0
        let controller = makeClearingController(
            store: store, platformOps: FakePlatformOps(), configDidChange: { notified += 1 })

        controller.clearBrowsingData([.pagePermissionExceptions], from: row.range)

        #expect(store.config.pagePermissionExceptions(.camera).map(\.host) == row.camera)
        #expect(store.config.pagePermissionExceptions(.microphone).map(\.host) == row.microphone)
        #expect(notified == 1)
    }

    /// An exception changed exactly at the range's start is inside it (「不早于起点」).
    @Test func anExceptionModifiedExactlyAtTheStartIsCleared() {
        let start = Self.clearingNow.addingTimeInterval(-3_600)
        let store = PersistedStore(
            WidgetConfig().updatingPagePermissionException(.camera, host: "edge.example", setting: .allow, modifiedAt: start))
        let controller = makeClearingController(store: store, platformOps: FakePlatformOps())

        controller.clearBrowsingData([.pagePermissionExceptions], from: .pastHour)

        #expect(store.config.pagePermissionExceptions(.camera).isEmpty)
    }

    @Test func clearingOnlyPagePermissionExceptionsNeverReachesThePlatform() {
        let fake = FakePlatformOps()
        let controller = makeClearingController(store: PersistedStore(Self.configWithExceptions()), platformOps: fake)

        controller.clearBrowsingData([.pagePermissionExceptions], from: .allTime)

        #expect(fake.websiteDataRemovals.isEmpty)
    }

    @Test func clearingNothingDoesNothing() {
        let store = PersistedStore(Self.configWithExceptions())
        let fake = FakePlatformOps()
        let controller = makeClearingController(store: store, platformOps: fake)

        controller.clearBrowsingData([], from: .allTime)

        #expect(fake.websiteDataRemovals.isEmpty)
        #expect(store.writeCount == 0)
    }

    // MARK: - #110: 历史记录 in 清除浏览数据… and 移除历史记录项目

    /// A real in-memory history at `clearingNow`'s clock: one page visited 40 days ago, one 3 days
    /// ago, one 2 hours ago and one 30 minutes ago.
    private func makeHistory() -> HistoryStore {
        let clock = TestClock(Self.clearingNow)
        let history = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        for (path, secondsAgo) in [("/40-days", 40 * 86_400.0), ("/3-days", 3 * 86_400), ("/2-hours", 7_200), ("/30-minutes", 1_800)] {
            clock.now = Self.clearingNow.addingTimeInterval(-secondsAgo)
            history.recordVisit(to: URL(string: "https://example.com\(path)")!)
        }
        clock.now = Self.clearingNow
        return history
    }

    private func paths(in history: HistoryStore) -> [String] {
        history.visits(since: .distantPast).map(\.url.path)
    }

    private func makeHistoryController(
        store: PersistedStore, platformOps: FakePlatformOps = FakePlatformOps(), history: HistoryStore
    ) -> SettingsController {
        let controller = SettingsController(
            platformOps: platformOps, currentConfig: { store.config }, persist: store.persist, historyStore: history)
        controller.currentDate = { Self.clearingNow }
        return controller
    }

    @Test(arguments: [
        (range: BrowsingDataTimeRange.pastHour, kept: ["/2-hours", "/3-days", "/40-days"]),
        (range: .past24Hours, kept: ["/3-days", "/40-days"]),
        (range: .past7Days, kept: ["/40-days"]),
        (range: .allTime, kept: []),
    ])
    func clearingHistoryRemovesThePagesVisitedWithinTheRange(_ row: (range: BrowsingDataTimeRange, kept: [String])) {
        let history = makeHistory()
        let controller = makeHistoryController(store: PersistedStore(WidgetConfig()), history: history)

        controller.clearBrowsingData([.history], from: row.range)

        #expect(paths(in: history) == row.kept)
    }

    /// 只想清历史、不想退出登录: ticking only 历史记录 never asks the platform to remove website
    /// data, and isn't a config edit either.
    @Test func clearingOnlyHistoryLeavesWebsiteDataAndTheConfigAlone() {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeHistoryController(store: store, platformOps: fake, history: makeHistory())

        controller.clearBrowsingData([.history], from: .allTime)

        #expect(fake.websiteDataRemovals.isEmpty)
        #expect(store.writeCount == 0)
    }

    @Test func historyIsLeftAloneWhenItIsNotTicked() {
        let history = makeHistory()
        let fake = FakePlatformOps()
        let controller = makeHistoryController(store: PersistedStore(WidgetConfig()), platformOps: fake, history: history)

        controller.clearBrowsingData([.websiteData, .cache], from: .allTime)

        #expect(paths(in: history).count == 4)
        #expect(fake.websiteDataRemovals.count == 1)
    }

    /// #117: a visit's site icon belongs to history, not to 缓存的图片和文件 — clearing the caches
    /// (or every kind of website data) leaves history's icons as they were.
    @Test func clearingTheCachesLeavesHistorysIcons() throws {
        let history = makeHistory()
        let icon = Data("an icon".utf8)
        let visit = try #require(history.visits(since: .distantPast).first)
        history.updateFavicon(icon, ofVisit: visit.id)
        let iconID = try #require(history.visits(since: .distantPast).first?.faviconID)
        let fake = FakePlatformOps()
        let controller = makeHistoryController(store: PersistedStore(WidgetConfig()), platformOps: fake, history: history)

        controller.clearBrowsingData([.cache], from: .allTime)
        controller.clearBrowsingData([.websiteData, .cache, .pagePermissionExceptions], from: .allTime)

        #expect(fake.websiteDataRemovals.count == 2)
        #expect(history.favicon(iconID) == icon)
        #expect(history.visits(since: .distantPast).first?.faviconID == iconID)
    }

    @Test func historyIsClearedAlongWithWebsiteData() {
        let history = makeHistory()
        let fake = FakePlatformOps()
        let controller = makeHistoryController(store: PersistedStore(WidgetConfig()), platformOps: fake, history: history)

        controller.clearBrowsingData(BrowsingDataKind.defaultSelection, from: .pastHour)

        #expect(paths(in: history) == ["/2-hours", "/3-days", "/40-days"])
        #expect(fake.websiteDataRemovals.map(\.types) == [[.cookiesAndOtherData, .cache]])
    }

    /// 改短保留期限: what's now past the limit goes at once, not at the next launch.
    @Test(arguments: [
        (retention: HistoryRetention.oneDay, kept: ["/30-minutes", "/2-hours"]),
        (retention: .oneWeek, kept: ["/30-minutes", "/2-hours", "/3-days"]),
        (retention: .oneMonth, kept: ["/30-minutes", "/2-hours", "/3-days"]),
        (retention: .oneYear, kept: ["/30-minutes", "/2-hours", "/3-days", "/40-days"]),
        (retention: .manual, kept: ["/30-minutes", "/2-hours", "/3-days", "/40-days"]),
    ])
    func changingTheRetentionRemovesWhatIsNowExpired(_ row: (retention: HistoryRetention, kept: [String])) {
        let store = PersistedStore(WidgetConfig())
        let history = makeHistory()
        let controller = makeHistoryController(store: store, history: history)

        controller.updateHistoryRetention(row.retention)

        #expect(store.config.historyRetention == row.retention)
        #expect(paths(in: history) == row.kept)
    }

    @Test func changingTheRetentionNotifiesLikeEveryOtherEdit() {
        let store = PersistedStore(WidgetConfig())
        var notified = 0
        let controller = SettingsController(
            platformOps: FakePlatformOps(), currentConfig: { store.config }, persist: store.persist,
            configDidChange: { notified += 1 }, historyStore: makeHistory())

        controller.updateHistoryRetention(.oneWeek)

        #expect(notified == 1)
        #expect(store.writeCount == 1)
    }

    // MARK: 管理网站和数据… (#106)

    private func configWithMeetExceptions() -> WidgetConfig {
        WidgetConfig(url: nil)
            .updatingPagePermissionException(.camera, host: "meet.google.com", setting: .allow, modifiedAt: Date())
            .updatingPagePermissionException(.microphone, host: "meet.google.com", setting: .deny, modifiedAt: Date())
            .updatingPagePermissionException(.camera, host: "zoom.us", setting: .allow, modifiedAt: Date())
    }

    private func managedWebsites(of controller: SettingsController) -> [ManagedWebsite] {
        var result: [ManagedWebsite] = []
        controller.fetchManagedWebsites { result = $0 }
        return result
    }

    @Test func managedWebsitesGroupThePlatformsRecordsWithTheConfigsExceptions() {
        let store = PersistedStore(configWithMeetExceptions())
        let fake = FakePlatformOps()
        fake.websiteDataRecords = [WebsiteDataRecord(displayName: "google.com", kinds: [.cookies])]
        let controller = makeController(store: store, platformOps: fake)

        #expect(managedWebsites(of: controller).map(\.domain) == ["google.com", "zoom.us"])
    }

    @Test func removingWebsiteDataRemovesTheRecordsWithoutTouchingTheExceptions() {
        let store = PersistedStore(configWithMeetExceptions())
        let fake = FakePlatformOps()
        fake.websiteDataRecords = [
            WebsiteDataRecord(displayName: "google.com", kinds: [.cookies]),
            WebsiteDataRecord(displayName: "example.com", kinds: [.cache]),
        ]
        var notified = 0
        let controller = makeController(store: store, platformOps: fake, configDidChange: { notified += 1 })
        let google = managedWebsites(of: controller).filter { $0.domain == "google.com" || $0.domain == "zoom.us" }
        var completed = false

        controller.removeWebsiteData(of: google) { completed = true }

        #expect(fake.websiteDataRecordRemovals.map(\.recordNames) == [["google.com"]])
        #expect(fake.websiteDataRecordRemovals.map(\.kinds) == [Set(WebsiteDataKind.allCases)])
        #expect(completed)
        #expect(store.writeCount == 0)
        #expect(notified == 0)
        #expect(store.config.pagePermissionExceptions(.camera).map(\.host) == ["meet.google.com", "zoom.us"])
    }

    @Test func removingTheDataOfWebsitesWithNoneSkipsThePlatform() {
        let store = PersistedStore(configWithMeetExceptions())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)
        var completed = false

        controller.removeWebsiteData(of: managedWebsites(of: controller)) { completed = true }

        #expect(fake.websiteDataRecordRemovals.isEmpty)
        #expect(completed)
    }

    @Test func resettingPagePermissionsRemovesEveryExceptionOfTheWebsitesHostsOnly() {
        let store = PersistedStore(configWithMeetExceptions())
        let fake = FakePlatformOps()
        fake.websiteDataRecords = [WebsiteDataRecord(displayName: "google.com", kinds: [.cookies])]
        var notified = 0
        let controller = makeController(store: store, platformOps: fake, configDidChange: { notified += 1 })
        let google = managedWebsites(of: controller).filter { $0.domain == "google.com" }

        controller.resetPagePermissions(of: google)

        #expect(store.config.pagePermissionExceptions(.camera).map(\.host) == ["zoom.us"])
        #expect(store.config.pagePermissionExceptions(.microphone).isEmpty)
        #expect(fake.websiteDataRecordRemovals.isEmpty)
        #expect(notified == 1)
    }

    @Test func resettingThePermissionsOfWebsitesWithoutExceptionsWritesNothing() {
        let store = PersistedStore(WidgetConfig(url: nil))
        let fake = FakePlatformOps()
        fake.websiteDataRecords = [WebsiteDataRecord(displayName: "google.com", kinds: [.cookies])]
        let controller = makeController(store: store, platformOps: fake)

        controller.resetPagePermissions(of: managedWebsites(of: controller))

        #expect(store.writeCount == 0)
    }

    @Test func removingAllWebsitesDataRemovesEveryRecordAndKeepsTheExceptions() {
        let store = PersistedStore(configWithMeetExceptions())
        let fake = FakePlatformOps()
        fake.websiteDataRecords = [
            WebsiteDataRecord(displayName: "google.com", kinds: [.cookies]),
            WebsiteDataRecord(displayName: "example.com", kinds: [.cache]),
        ]
        let controller = makeController(store: store, platformOps: fake)
        var completed = false

        controller.removeDataOfAllWebsites { completed = true }

        #expect(fake.websiteDataRecordRemovals.map(\.recordNames) == [["google.com", "example.com"]])
        #expect(fake.websiteDataRecordRemovals.map(\.kinds) == [Set(WebsiteDataKind.allCases)])
        #expect(completed)
        #expect(store.writeCount == 0)
        #expect(managedWebsites(of: controller).map(\.domain) == ["meet.google.com", "zoom.us"])
    }

    @Test func aWebInspectorEditReachesTheLiveWindowWhenWiredToTheOrchestrator() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { store.config })
        orchestrator.start()
        let controller = makeController(store: store, platformOps: fake, configDidChange: orchestrator.reapplyConfiguration)

        controller.updateWebInspectorEnabled(true)

        #expect(fake.webInspectableChanges.map(\.enabled) == [false, true])
    }

    // MARK: - #67: 弹出式窗口

    @Test func updatingPopupWindowPolicyPersistsAndNotifies() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.updatePopupWindowPolicy(.allow)

        #expect(store.config.popupWindowPolicy == .allow)
        #expect(store.config.url == URL(string: "https://example.com"))
        #expect(notified == 1)
    }

    /// 改动即时生效: the edit reaches the open widget's web view without a reopen.
    @Test func aPopupWindowPolicyEditReachesTheLiveWindowWhenWiredToTheOrchestrator() {
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { store.config })
        orchestrator.start()
        let controller = makeController(store: store, platformOps: fake, configDidChange: orchestrator.reapplyConfiguration)

        controller.updatePopupWindowPolicy(.allow)
        controller.updatePopupWindowPolicy(.block)

        #expect(fake.popupWindowsAllowedChanges.map(\.allowed) == [false, true, false])
    }
    // MARK: 视频控制 (#79)

    private static let backtick = Hotkey(keyCode: 0x32, modifierFlags: 0x1000)

    @Test func rebindingAVideoActionPersistsItAndNotifies() {
        let store = PersistedStore(WidgetConfig())
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        let rejection = controller.updateVideoControlTrigger(.keystroke(Self.backtick), for: .togglePlayback)

        #expect(rejection == nil)
        #expect(store.config.videoControlTrigger(for: .togglePlayback) == .keystroke(Self.backtick))
        #expect(notified == 1)
    }

    @Test func rebindingAVideoActionNeverTouchesTheSystemHotkeyTable() {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        controller.updateVideoControlTrigger(.keystroke(Self.backtick), for: .togglePlayback)
        controller.updateVideoControlTrigger(nil, for: .togglePlayback)

        #expect(fake.hotkeyCallOrder.isEmpty)
    }

    @Test func clearingAVideoActionUnbindsIt() {
        let store = PersistedStore(WidgetConfig())
        let controller = makeController(store: store)

        controller.updateVideoControlTrigger(nil, for: .seekBackward)

        #expect(store.config.videoControlTrigger(for: .seekBackward) == nil)
    }

    @Test func updatingTheSeekStepPersistsItClamped() {
        let store = PersistedStore(WidgetConfig())
        let controller = makeController(store: store)

        controller.updateVideoSeekStep(90)

        #expect(store.config.videoSeekStep == 60)
    }

    @Test func resettingVideoControlRestoresEveryDefaultAndTheStep() {
        let store = PersistedStore(
            WidgetConfig()
                .updatingVideoControlTrigger(nil, for: .togglePlayback)
                .updatingVideoControlTrigger(.modifierTap(.rightOption), for: .seekForward)
                .updatingVideoSeekStep(12))
        let controller = makeController(store: store)

        controller.resetVideoControlToDefaults()

        #expect(store.config.videoControlOverrides.isEmpty)
        #expect(store.config.videoSeekStep == WidgetConfig.defaultVideoSeekStep)
    }

    /// Every way a video key can collide with something already in use, refused with the reason
    /// naming what holds it (#86) and leaving the config untouched.
    @Test(arguments: [
        (name: "an action hotkey", trigger: TriggerKey.keystroke(DefaultHotkeys.toggleGhostMode),
         reason: HotkeyRejection.conflictsWithAction(.toggleGhostMode)),
        (name: "a local menu shortcut", trigger: .keystroke(DefaultHotkeys.openSettings), reason: .reservedMenuShortcut),
        (name: "a mapping trigger", trigger: .keystroke(Hotkey(keyCode: 0x12, modifierFlags: 0x0800)),
         reason: .conflictsWithMapping(HotkeyMapping(trigger: Hotkey(keyCode: 0x12, modifierFlags: 0x0800), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0x1000)))),
        (name: "another video action's double tap", trigger: .modifierDoubleTap(.rightCommand), reason: .conflictsWithVideoControl(.seekBackward)),
        (name: "another video action's keystroke", trigger: .keystroke(Hotkey(keyCode: 0x26, modifierFlags: 0x1000)),
         reason: .conflictsWithVideoControl(.seekForward)),
    ])
    func refusesAVideoKeyThatIsAlreadyInUse(_ scenario: (name: String, trigger: TriggerKey, reason: HotkeyRejection)) {
        let original = WidgetConfig(
            hotkeyMappings: [HotkeyMapping(trigger: Hotkey(keyCode: 0x12, modifierFlags: 0x0800), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0x1000))]
        ).updatingVideoControlTrigger(.keystroke(Hotkey(keyCode: 0x26, modifierFlags: 0x1000)), for: .seekForward)
        let store = PersistedStore(original)
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateVideoControlTrigger(scenario.trigger, for: .togglePlayback)

        #expect(rejection == scenario.reason, "\(scenario.name)")
        #expect(store.config == original, "\(scenario.name)")
        #expect(fake.presentedAlerts.isEmpty, "\(scenario.name)")
    }

    @Test func rebindingAVideoActionToItsOwnCurrentKeyIsNotAConflict() {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        #expect(controller.updateVideoControlTrigger(.modifierTap(.rightOption), for: .togglePlayback) == nil)
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func anActionHotkeyCannotTakeAKeyAVideoActionHolds() {
        let store = PersistedStore(WidgetConfig().updatingVideoControlTrigger(.keystroke(Self.backtick), for: .togglePlayback))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.hideWidget, to: Self.backtick)

        #expect(rejection == .conflictsWithVideoControl(.togglePlayback))
        #expect(store.config.hotkey(for: .hideWidget) == DefaultHotkeys.hideWidget)
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test func aMappingTriggerCannotTakeAKeyAVideoActionHolds() {
        let store = PersistedStore(WidgetConfig().updatingVideoControlTrigger(.keystroke(Self.backtick), for: .seekForward))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(trigger: Self.backtick, pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0x1000))

        #expect(rejection == .conflictsWithVideoControl(.seekForward))
        #expect(store.config.hotkeyMappings.isEmpty)
    }

    // MARK: #89 组合键必须带修饰键

    /// J, ⇧J, ⇧1 and ⇧↑: each would take a character, or text selection, away from every app
    /// while Mochi runs.
    private static let combosThatKeepACharacter = [
        Hotkey(keyCode: 0x26, modifierFlags: 0), Hotkey(keyCode: 0x26, modifierFlags: 0x0200),
        Hotkey(keyCode: 0x12, modifierFlags: 0x0200), Hotkey(keyCode: 0x7E, modifierFlags: 0x0200),
    ]

    /// ⌥J, ⌃⇧K and ⇧F5 — the last because an F-key types nothing, with or without ⇧.
    private static let combosWithAModifier = [
        Hotkey(keyCode: 0x26, modifierFlags: 0x0800), Hotkey(keyCode: 0x28, modifierFlags: 0x1200),
        Hotkey(keyCode: 0x60, modifierFlags: 0x0200),
    ]

    @Test(arguments: combosWithAModifier)
    func anActionHotkeyWithAModifierIsAccepted(_ combo: Hotkey) {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        #expect(controller.updateActionHotkey(.hideWidget, to: combo) == nil)
        #expect(store.config.hotkey(for: .hideWidget) == combo)
        #expect(fake.registeredHotkeys == [combo])
    }

    @Test(arguments: combosThatKeepACharacter)
    func anActionHotkeyMustCarryAModifierOtherThanShift(_ combo: Hotkey) {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateActionHotkey(.hideWidget, to: combo)

        #expect(rejection == .missingModifier)
        #expect(store.config.hotkey(for: .hideWidget) == DefaultHotkeys.hideWidget)
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.unregisteredHotkeys.isEmpty)
    }

    @Test(arguments: combosThatKeepACharacter)
    func aNewMappingsTriggerMustCarryAModifierOtherThanShift(_ combo: Hotkey) {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.addHotkeyMapping(trigger: combo, pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))

        #expect(rejection == .missingModifier)
        #expect(store.config.hotkeyMappings.isEmpty)
        #expect(fake.registeredHotkeys.isEmpty)
    }

    @Test(arguments: combosThatKeepACharacter)
    func anEditedMappingsTriggerMustCarryAModifierOtherThanShift(_ combo: Hotkey) {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 0x01, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: combo, pageKeystroke: existing.pageKeystroke)

        #expect(rejection == .missingModifier)
        #expect(store.config.hotkeyMappings == [existing])
        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.unregisteredHotkeys.isEmpty)
    }

    @Test(arguments: combosThatKeepACharacter)
    func aVideoKeystrokeMustCarryAModifierOtherThanShift(_ combo: Hotkey) {
        let store = PersistedStore(WidgetConfig())
        let controller = makeController(store: store)

        let rejection = controller.updateVideoControlTrigger(.keystroke(combo), for: .seekForward)

        #expect(rejection == .missingModifier)
        #expect(store.config.videoControlTrigger(for: .seekForward) == VideoControlAction.seekForward.defaultTrigger)
    }

    @Test(arguments: combosWithAModifier)
    func aNewMappingsTriggerWithAModifierIsAccepted(_ combo: Hotkey) {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        #expect(controller.addHotkeyMapping(trigger: .keystroke(combo), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0)) == nil)
        #expect(fake.registeredHotkeys == [combo])
    }

    @Test(arguments: combosWithAModifier)
    func anEditedMappingsTriggerWithAModifierIsAccepted(_ combo: Hotkey) {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 0x01, modifierFlags: 0x1000), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(hotkeyMappings: [existing]))
        let controller = makeController(store: store)

        #expect(controller.updateHotkeyMapping(at: 0, trigger: .keystroke(combo), pageKeystroke: existing.pageKeystroke) == nil)
        #expect(store.config.hotkeyMappings.map(\.trigger) == [.keystroke(combo)])
    }

    @Test(arguments: combosWithAModifier)
    func aVideoKeystrokeWithAModifierIsAccepted(_ combo: Hotkey) {
        let store = PersistedStore(WidgetConfig())
        let controller = makeController(store: store)

        #expect(controller.updateVideoControlTrigger(.keystroke(combo), for: .seekForward) == nil)
        #expect(store.config.videoControlTrigger(for: .seekForward) == .keystroke(combo))
    }

    /// Every row judges a recorded combo the same way: a bare key is refused for lacking a
    /// modifier even when an older binding also happens to hold it.
    @Test func aBareVideoKeyHeldByAnOlderBindingIsRefusedForItsMissingModifier() {
        let bare = Hotkey(keyCode: 0x26, modifierFlags: 0)
        let store = PersistedStore(WidgetConfig().updatingVideoControlTrigger(.keystroke(bare), for: .seekForward))
        let controller = makeController(store: store)

        #expect(controller.updateVideoControlTrigger(.keystroke(bare), for: .seekBackward) == .missingModifier)
    }

    /// 恢复默认热键 (#88) leaves the opacity — set on the same pane — where it is.
    @Test func restoringDefaultHotkeysLeavesTheGhostOpacityAlone() {
        let store = PersistedStore(WidgetConfig()
            .updatingVideoControlTrigger(.modifierTap(.leftControl), for: .togglePlayback))
        let controller = makeController(store: store)
        controller.updateGhostOpacity(0.3)

        controller.resetVideoControlToDefaults()
        controller.resetActionHotkeysToDefaults()

        #expect(store.config.ghostOpacity == 0.3)
        #expect(store.config.videoControlTrigger(for: .togglePlayback) == .modifierTap(.rightOption))
    }

    /// The page side is a keystroke to send, not a key to listen for: a bare key is exactly what
    /// most players want.
    @Test func aMappingsPageKeystrokeMayBeABareKey() {
        let store = PersistedStore(WidgetConfig())
        let controller = makeController(store: store)

        #expect(controller.addHotkeyMapping(trigger: Hotkey(keyCode: 0x26, modifierFlags: 0x0800), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0)) == nil)
        #expect(store.config.hotkeyMappings.count == 1)
    }

    /// The rule judges what is being recorded, not what is already there: a bare trigger saved
    /// before #89 doesn't block editing the rest of its mapping.
    @Test func aMappingWithABareTriggerSavedBeforeTheRuleCanStillHaveItsPageKeyEdited() {
        let legacy = HotkeyMapping(trigger: Hotkey(keyCode: 0x28, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(hotkeyMappings: [legacy]))
        let controller = makeController(store: store)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: legacy.trigger, pageKeystroke: Hotkey(keyCode: 0x24, modifierFlags: 0))

        #expect(rejection == nil)
        #expect(store.config.hotkeyMappings.map(\.pageKeystroke) == [Hotkey(keyCode: 0x24, modifierFlags: 0)])
    }

    // MARK: #91 连按两次

    /// One key, two actions: a tap and a double tap of right ⌥ are different trigger keys.
    @Test func aKeysTapAndItsDoubleTapMayGoToDifferentVideoActions() {
        let store = PersistedStore(.tapsOnlyVideoKeys)
        let controller = makeController(store: store)

        let rejection = controller.updateVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekBackward)

        #expect(rejection == nil)
        #expect(store.config.videoControlTrigger(for: .togglePlayback) == .modifierTap(.rightOption))
        #expect(store.config.videoControlTrigger(for: .seekBackward) == .modifierDoubleTap(.rightOption))
    }

    @Test func theSameDoubleTapCannotGoToTwoVideoActions() {
        let store = PersistedStore(WidgetConfig.tapsOnlyVideoKeys.updatingVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekBackward))
        let controller = makeController(store: store)

        let rejection = controller.updateVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekForward)

        #expect(rejection == .conflictsWithVideoControl(.seekBackward))
        #expect(store.config.videoControlTrigger(for: .seekForward) == nil)
    }

    // MARK: #92 热键传递的轻按 / 连按两次

    @Test(arguments: [TriggerKey.modifierTap(.leftControl), .modifierDoubleTap(.leftControl)])
    func aTapMappingIsAddedWithoutTouchingTheSystemHotkeyTable(_ trigger: TriggerKey) {
        let store = PersistedStore(WidgetConfig())
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        #expect(controller.addHotkeyMapping(trigger: trigger, pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0)) == nil)
        controller.removeHotkeyMapping(at: 0)

        #expect(fake.registeredHotkeys.isEmpty)
        #expect(fake.unregisteredHotkeys.isEmpty)
        #expect(store.config.hotkeyMappings.isEmpty)
    }

    @Test func aTapMappingCannotTakeAVideoKeysTap() {
        let store = PersistedStore(WidgetConfig())
        let controller = makeController(store: store)

        let rejection = controller.addHotkeyMapping(trigger: .modifierTap(.rightOption), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))

        #expect(rejection == .conflictsWithVideoControl(.togglePlayback))
        #expect(store.config.hotkeyMappings.isEmpty)
    }

    @Test func aVideoKeyCannotTakeAMappingsDoubleTap() {
        let mapping = HotkeyMapping(trigger: .modifierDoubleTap(.rightOption), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        var config = WidgetConfig.tapsOnlyVideoKeys
        config.hotkeyMappings = [mapping]
        let store = PersistedStore(config)
        let controller = makeController(store: store)

        let rejection = controller.updateVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekForward)

        #expect(rejection == .conflictsWithMapping(mapping))
        #expect(store.config.videoControlTrigger(for: .seekForward) == nil)
    }

    /// The same key both ways across the two features is allowed, like within 视频控制 (#91).
    @Test func aMappingMayTakeTheDoubleTapOfAVideoKeysTap() {
        let store = PersistedStore(.tapsOnlyVideoKeys)
        let controller = makeController(store: store)

        #expect(controller.addHotkeyMapping(trigger: .modifierDoubleTap(.rightOption), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0)) == nil)
    }

    @Test func turningAComboMappingIntoATapReleasesTheCombo() {
        let combo = Hotkey(keyCode: 0x26, modifierFlags: 0x1000)
        let existing = HotkeyMapping(trigger: combo, pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let rejection = controller.updateHotkeyMapping(at: 0, trigger: .modifierTap(.leftControl), pageKeystroke: existing.pageKeystroke)

        #expect(rejection == nil)
        #expect(fake.hotkeyCallOrder == [.unregister(combo)])
        #expect(store.config.hotkeyMappings.map(\.trigger) == [.modifierTap(.leftControl)])
    }

    // MARK: 系统权限 (#98)

    @Test func promptsForAccessibilityOnlyWhileItIsNotGranted() {
        let fake = FakePlatformOps()
        let config = WidgetConfig().updatingVideoControlTrigger(
            .keystroke(Hotkey(keyCode: 0x23, modifierFlags: 0x0800)), for: .seekForward)  // ⌥P
        let controller = makeController(store: PersistedStore(config), platformOps: fake)

        #expect(controller.systemPermissionPrompts.isEmpty)
        fake.stubbedSystemPermissionStatuses[.accessibility] = .denied

        #expect(controller.systemPermissionPrompts.filter { $0.placement == .hotkeysPanelTop }
            == [SystemPermissionPrompt(permission: .accessibility, placement: .hotkeysPanelTop, action: .request)])
    }

    /// The system can't tell 未询问 from 已拒绝 for Accessibility (ADR-0029): asking from the panel
    /// is noted in the same marker as 视频控制's own request, so from then on the button sends the
    /// user to System Settings instead of asking again.
    @Test func requestingAccessibilityFromThePanelTurnsItsButtonIntoOpenSystemSettings() throws {
        let fake = FakePlatformOps()
        fake.stubbedSystemPermissionStatuses[.accessibility] = .denied
        let config = WidgetConfig().updatingVideoControlTrigger(
            .keystroke(Hotkey(keyCode: 0x23, modifierFlags: 0x0800)), for: .seekForward)  // ⌥P
        let controller = makeController(store: PersistedStore(config), platformOps: fake)
        let prompt = try #require(controller.systemPermissionPrompts.first { $0.placement == .hotkeysPanelTop })

        controller.perform(prompt)

        #expect(fake.systemPermissionRequests == [.accessibility])
        #expect(fake.systemPermissionMarkers == [.accessibilityRequested])
        #expect(controller.systemPermissionPrompts.map(\.action) == [.openSystemSettings, .openSystemSettings])
    }

    /// The prompts follow the config the panel is editing (#111): rebinding the one key that
    /// needs Accessibility to a tap takes its prompt away.
    @Test func accessibilityPromptGoesOnceNothingNeedsIt() {
        let fake = FakePlatformOps()
        fake.stubbedSystemPermissionStatuses[.accessibility] = .denied
        let config = WidgetConfig().updatingVideoControlTrigger(
            .keystroke(Hotkey(keyCode: 0x23, modifierFlags: 0x0800)), for: .seekForward)  // ⌥P
        let controller = makeController(store: PersistedStore(config), platformOps: fake)
        #expect(!controller.systemPermissionPrompts.isEmpty)

        _ = controller.updateVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekForward)

        #expect(controller.systemPermissionPrompts.isEmpty)
    }

    @Test(arguments: [
        (action: SystemPermissionPrompt.Action.openSystemSettings, requested: [SystemPermission](), opened: [SystemPermission.camera]),
        (action: .request, requested: [.camera], opened: []),
    ])
    func aPromptsButtonGoesToThePlatformForItsPermission(
        _ row: (action: SystemPermissionPrompt.Action, requested: [SystemPermission], opened: [SystemPermission])
    ) {
        let fake = FakePlatformOps()
        let controller = makeController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        controller.perform(SystemPermissionPrompt(permission: .camera, placement: .hotkeysPanelTop, action: row.action))

        #expect(fake.systemPermissionRequests == row.requested)
        #expect(fake.openedSystemSettings == row.opened)
        #expect(fake.systemPermissionMarkers.isEmpty)
    }

    @Test func aPromptWithoutAButtonDoesNothing() {
        let fake = FakePlatformOps()
        let controller = makeController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        controller.perform(SystemPermissionPrompt(permission: .camera, placement: .hotkeysPanelTop, action: nil))

        #expect(fake.systemPermissionRequests.isEmpty)
        #expect(fake.openedSystemSettings.isEmpty)
    }

    /// System Settings changes a permission behind Mochi's back — the panel hears about it through
    /// the platform's one "may have changed" signal, not by watching the app itself.
    @Test func passesOnThatSystemPermissionsMayHaveChanged() {
        let fake = FakePlatformOps()
        let controller = makeController(store: PersistedStore(WidgetConfig()), platformOps: fake)
        var heard = 0

        controller.onSystemPermissionsMayHaveChanged { heard += 1 }
        fake.simulateSystemPermissionsMayHaveChanged()

        #expect(heard == 1)
    }

    // MARK: 摄像头 / 麦克风的系统权限 (#104)

    /// 网站 → 摄像头 / 麦克风: each page's button asks the platform about its own device — 请求权限
    /// for one the system has never asked about, 打开系统设置 for one it has refused.
    @Test(arguments: [
        (camera: SystemPermissionStatus.notDetermined, microphone: SystemPermissionStatus.denied,
         requested: [SystemPermission.camera], opened: [SystemPermission.microphone]),
        (camera: .denied, microphone: .notDetermined, requested: [.microphone], opened: [.camera]),
    ])
    func cameraAndMicrophonePromptsGoToThePlatformForTheirOwnDevice(
        _ row: (camera: SystemPermissionStatus, microphone: SystemPermissionStatus,
                requested: [SystemPermission], opened: [SystemPermission])
    ) {
        let fake = FakePlatformOps()
        fake.stubbedSystemPermissionStatuses = [.camera: row.camera, .microphone: row.microphone]
        let controller = makeController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        let prompts = controller.systemPermissionPrompts.filter { $0.placement == .websitesPermissionPage }
        prompts.forEach(controller.perform)

        #expect(prompts.map(\.permission) == [.camera, .microphone])
        #expect(fake.systemPermissionRequests == row.requested)
        #expect(fake.openedSystemSettings == row.opened)
    }

    /// Setting a page's 网页权限 to 拒绝 takes its prompt away straight off — the prompts are read
    /// from the config as it now stands.
    @Test func aDeniedPagePermissionTakesItsSystemPermissionPromptAway() {
        let fake = FakePlatformOps()
        fake.stubbedSystemPermissionStatuses = [.camera: .denied, .microphone: .denied]
        let controller = makeController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        controller.updateCameraPermission(.deny)

        #expect(controller.systemPermissionPrompts.map(\.permission) == [.microphone])
    }

    /// #105: the Downloads folder's prompt follows the remembered refusal of its last write — kept
    /// in `UserDefaults`, so it is there from the first look after a relaunch — and its button
    /// opens 文件和文件夹.
    @Test func promptsForTheDownloadsFolderWhileItsLastWriteStandsRefused() {
        let fake = FakePlatformOps()
        let controller = makeController(store: PersistedStore(WidgetConfig()), platformOps: fake)

        #expect(controller.systemPermissionPrompts.isEmpty)
        fake.systemPermissionMarkers.insert(.downloadsFolderWriteDenied)
        let prompts = controller.systemPermissionPrompts

        #expect(prompts.map(\.permission) == [.downloadsFolder])
        prompts.forEach(controller.perform)
        #expect(fake.openedSystemSettings == [.downloadsFolder])
    }

    // MARK: 网站 → 摄像头 / 麦克风's exceptions (#109)

    private static let earlier = Date(timeIntervalSince1970: 1_700_000_000)
    private static let editedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func configWithExceptions() -> WidgetConfig {
        WidgetConfig()
            .updatingPagePermissionException(.camera, host: "meet.example.com", setting: .allow, modifiedAt: Self.earlier)
            .updatingPagePermissionException(.camera, host: "chat.example.com", setting: .ask, modifiedAt: Self.earlier)
            .updatingPagePermissionException(.camera, host: "video.example.org", setting: .deny, modifiedAt: Self.earlier)
            .updatingPagePermissionException(.microphone, host: "meet.example.com", setting: .allow, modifiedAt: Self.earlier)
    }

    /// Changing an exception's setting in the table writes it back to that website's exception and
    /// stamps it — the time 清除浏览数据 goes by — leaving the others and the other device alone.
    @Test(arguments: PagePermission.allCases)
    func changingAnExceptionsSettingWritesItBackStampedWithTheTimeOfTheEdit(_ permission: PagePermission) {
        let store = PersistedStore(configWithExceptions())
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })
        controller.currentDate = { Self.editedAt }
        let other: PagePermission = permission == .camera ? .microphone : .camera
        let othersBefore = store.config.pagePermissionExceptions(other)

        controller.updatePagePermissionException(permission, host: "meet.example.com", setting: .deny)

        let edited = store.config.pagePermissionExceptions(permission).first { $0.host == "meet.example.com" }
        #expect(edited == WidgetConfig.PagePermissionException(host: "meet.example.com", setting: .deny, lastModified: Self.editedAt))
        #expect(store.config.pagePermissionSetting(permission, forHost: "meet.example.com") == .deny)
        #expect(store.config.pagePermissionExceptions(permission).filter { $0.host != "meet.example.com" }
            .allSatisfy { $0.lastModified == Self.earlier })
        #expect(store.config.pagePermissionExceptions(other) == othersBefore)
        #expect(store.writeCount == 1)
        #expect(notified == 1)
    }

    /// 移除 deletes the selected websites' exceptions in one write, sending them back to the default.
    @Test func removingExceptionsDeletesThemAndSendsThoseWebsitesBackToTheDefault() {
        let store = PersistedStore(configWithExceptions().updatingCameraPermission(.ask))
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.removePagePermissionExceptions(.camera, hosts: ["meet.example.com", "video.example.org"])

        #expect(store.config.pagePermissionExceptions(.camera).map(\.host) == ["chat.example.com"])
        #expect(store.config.pagePermissionSetting(.camera, forHost: "video.example.org") == .ask)
        #expect(store.config.pagePermissionExceptions(.microphone).map(\.host) == ["meet.example.com"])
        #expect(store.writeCount == 1)
        #expect(notified == 1)
    }

    /// Removing nothing writes nothing.
    @Test func removingNoExceptionsTouchesNothing() {
        let store = PersistedStore(configWithExceptions())
        var notified = 0
        let controller = makeController(store: store, configDidChange: { notified += 1 })

        controller.removePagePermissionExceptions(.camera, hosts: [])

        #expect(store.writeCount == 0)
        #expect(notified == 0)
    }

    /// The page's 系统权限 prompt follows the exceptions too: allowing one website while the default
    /// is 拒绝 brings the prompt back, and removing that exception takes it away again.
    @Test func anExceptionEditBringsTheSystemPermissionPromptBackOrTakesItAway() {
        let fake = FakePlatformOps()
        fake.stubbedSystemPermissionStatuses = [.camera: .denied, .microphone: .authorized]
        let store = PersistedStore(WidgetConfig().updatingCameraPermission(.deny)
            .updatingPagePermissionException(.camera, host: "meet.example.com", setting: .deny, modifiedAt: Self.earlier))
        let controller = makeController(store: store, platformOps: fake)
        let before = controller.systemPermissionPrompts.filter { $0.permission == .camera }

        controller.updatePagePermissionException(.camera, host: "meet.example.com", setting: .allow)
        let shown = controller.systemPermissionPrompts.filter { $0.permission == .camera }
        controller.removePagePermissionExceptions(.camera, hosts: ["meet.example.com"])
        let hiddenAgain = controller.systemPermissionPrompts.filter { $0.permission == .camera }

        #expect(before.isEmpty)
        #expect(shown.map(\.action) == [.openSystemSettings])
        #expect(hiddenAgain.isEmpty)
    }
}
