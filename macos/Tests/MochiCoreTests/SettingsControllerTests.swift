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

    private func makeController(store: PersistedStore, platformOps: PlatformOps = FakePlatformOps()) -> SettingsController {
        SettingsController(platformOps: platformOps, currentConfig: { store.config }, persist: store.persist)
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

    @Test func addingAMappingWhoseTriggerCollidesWithADefaultHotkeyFailsWithoutTouchingTheOS() {
        // Regression test: `RegisterEventHotKey` does not fail on an in-process duplicate — it
        // installs a second, independently-firing handler — so a collision with one of Mochi's own
        // defaults must be caught before ever reaching `registerGlobalHotkey`, not by trusting its
        // return value (which would wrongly report success here).
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.addHotkeyMapping(trigger: DefaultHotkeys.reloadPage, pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

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

    @Test func updatingAMappingsTriggerToADefaultHotkeyFailsWithoutTouchingTheOS() {
        let existing = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 9, modifierFlags: 0))
        let store = PersistedStore(WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [existing]))
        let fake = FakePlatformOps()
        let controller = makeController(store: store, platformOps: fake)

        let succeeded = controller.updateHotkeyMapping(at: 0, trigger: DefaultHotkeys.togglePin, pageKeystroke: existing.pageKeystroke)

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
}
