import Foundation
import Testing

@testable import MochiCore

@Suite struct WidgetConfigTests {
    @Test func parsesURLFromTOML() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.url == URL(string: "https://example.com"))
    }

    // #16: a config with no `url` key at all is a valid, expected state (a fresh install with no
    // browsing history yet) rather than a config error — see `resolveStartupContent`, which falls
    // back to the Empty Page for exactly this case.
    @Test func urlIsNilWhenKeyMissingInsteadOfThrowing() throws {
        let config = try WidgetConfig.parse("")
        #expect(config.url == nil)
    }

    @Test func throwsWhenURLIsMalformed() {
        #expect(throws: WidgetConfigError.self) {
            try WidgetConfig.parse("url = \"\"")
        }
    }

    @Test func windowStateIsNilWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.windowState == nil)
    }

    @Test func parsesWindowStateWhenPresent() throws {
        let toml = """
        url = "https://example.com"

        [window]
        x = 10.0
        y = 20.0
        width = 800.0
        height = 600.0
        zoom = 1.25
        """

        let config = try WidgetConfig.parse(toml)

        #expect(
            config.windowState
                == WindowState(frame: WindowFrame(x: 10, y: 20, width: 800, height: 600), zoom: 1.25))
    }

    @Test func serializingThenReparsingRoundTripsWindowState() throws {
        let original = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 1, y: 2, width: 3, height: 4), zoom: 1.5)
        )

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func writingThenLoadingFromDiskRoundTrips() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 1, y: 2, width: 3, height: 4), zoom: 1.5)
        )

        try original.write(to: fileURL)
        let loaded = try WidgetConfig.load(from: fileURL)

        #expect(loaded == original)
    }

    @Test func serializingThenReparsingRoundTripsAnAbsentURL() throws {
        let original = WidgetConfig(url: nil, ghostOpacity: 0.3)

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
        #expect(reparsed.url == nil)
    }

    @Test func updatingWindowStateReturnsCopyWithNewStateOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let newState = WindowState(frame: WindowFrame(x: 0, y: 0, width: 100, height: 100), zoom: 2.0)

        let updated = config.updatingWindowState(newState)

        #expect(updated.windowState == newState)
        #expect(updated.url == config.url)
    }

    @Test func updatingURLReturnsCopyWithNewURLOnly() {
        let windowState = WindowState(frame: WindowFrame(x: 0, y: 0, width: 100, height: 100), zoom: 2.0)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, windowState: windowState)
        let newURL = URL(string: "https://example.org")!

        let updated = config.updatingURL(newURL)

        #expect(updated.url == newURL)
        #expect(updated.windowState == config.windowState)
    }

    @Test func ignoresALeftOverPinnedKeyInsteadOfThrowing() throws {
        // Pin was internalized into Ghost Mode (ADR-0012) and its config field deleted. No
        // migration code was written: TOML parsing is lenient about unknown keys, so an existing
        // config file keeps loading and the stale key is simply dropped on the next write.
        let toml = """
        url = "https://example.com"
        pinned = true
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.url == URL(string: "https://example.com")!)
        #expect(!config.serialized().contains("pinned"))
    }

    @Test func customScriptIsNilWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.customScript == nil)
    }

    @Test func parsesCustomScriptWhenPresent() throws {
        let toml = """
        url = "https://example.com"
        custom_script = "console.log('hi')"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.customScript == "console.log('hi')")
    }

    @Test func serializingThenReparsingRoundTripsCustomScript() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!, customScript: "document.title = 'x'")

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func ghostOpacityDefaultsWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.ghostOpacity == WidgetConfig.defaultGhostOpacity)
    }

    @Test func parsesGhostOpacityWhenPresent() throws {
        let toml = """
        url = "https://example.com"
        ghost_opacity = 0.35
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.ghostOpacity == 0.35)
    }

    @Test func serializingThenReparsingRoundTripsGhostOpacity() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.4)

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func snapThresholdDefaultsToWindowSnappingsDefaultWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.snapThreshold == WindowSnapping.defaultThreshold)
    }

    @Test func parsesSnapThresholdWhenPresent() throws {
        let toml = """
        url = "https://example.com"
        snap_threshold = 24.0
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.snapThreshold == 24.0)
    }

    @Test func serializingThenReparsingRoundTripsSnapThreshold() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!, snapThreshold: 32)

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func hotkeyMappingsIsEmptyWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.hotkeyMappings.isEmpty)
    }

    @Test func parsesHotkeyMappingsWhenPresent() throws {
        let toml = """
        url = "https://example.com"

        [[hotkey_mappings]]
        trigger_key_code = 49
        trigger_modifiers = 0
        page_key_code = 49
        page_modifiers = 0
        """

        let config = try WidgetConfig.parse(toml)

        #expect(
            config.hotkeyMappings == [
                HotkeyMapping(
                    trigger: Hotkey(keyCode: 49, modifierFlags: 0),
                    pageKeystroke: Hotkey(keyCode: 49, modifierFlags: 0)
                )
            ])
    }

    @Test func skipsAHotkeyMappingWithAnOutOfRangeValueInsteadOfCrashing() throws {
        // Regression test: hand-editing this table is the only way to configure it (until #14
        // ships a UI), so a negative or overflowing number must be skipped, not trap the app.
        let toml = """
        url = "https://example.com"

        [[hotkey_mappings]]
        trigger_key_code = 49
        trigger_modifiers = -1
        page_key_code = 49
        page_modifiers = 0
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkeyMappings.isEmpty)
    }

    @Test func skipsAHotkeyMappingWhoseKeyCodeDoesNotFitAVirtualKeyCode() throws {
        let toml = """
        url = "https://example.com"

        [[hotkey_mappings]]
        trigger_key_code = 49
        trigger_modifiers = 0
        page_key_code = 999999
        page_modifiers = 0
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkeyMappings.isEmpty)
    }

    @Test func serializingThenReparsingRoundTripsHotkeyMappings() throws {
        let original = WidgetConfig(
            url: URL(string: "https://example.com")!,
            hotkeyMappings: [
                HotkeyMapping(trigger: Hotkey(keyCode: 49, modifierFlags: 0x0100), pageKeystroke: Hotkey(keyCode: 49, modifierFlags: 0)),
                HotkeyMapping(trigger: Hotkey(keyCode: 4, modifierFlags: 0x0800), pageKeystroke: Hotkey(keyCode: 6, modifierFlags: 0)),
            ]
        )

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    // MARK: - #13/#16: startup target

    @Test func startupTargetIsNilWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.startupTarget == nil)
    }

    @Test func parsesStartupTargetURLWhenPresent() throws {
        let toml = """
        url = "https://example.com"

        [startup_target]
        kind = "url"
        url = "https://startup.example.com"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.startupTarget == .url(URL(string: "https://startup.example.com")!))
    }

    @Test func parsesStartupTargetEmptyPageWhenPresent() throws {
        let toml = """
        url = "https://example.com"

        [startup_target]
        kind = "empty_page"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.startupTarget == .emptyPage)
    }

    @Test func treatsAnUnknownStartupTargetKindAsAbsentInsteadOfCrashing() throws {
        let toml = """
        url = "https://example.com"

        [startup_target]
        kind = "something_else"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.startupTarget == nil)
    }

    @Test func serializingThenReparsingRoundTripsStartupTargetURL() throws {
        let original = WidgetConfig(
            url: URL(string: "https://example.com")!, startupTarget: .url(URL(string: "https://startup.example.com")!))

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func serializingThenReparsingRoundTripsStartupTargetEmptyPage() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!, startupTarget: .emptyPage)

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func updatingStartupTargetReturnsCopyWithNewStartupTargetOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        let updated = config.updatingStartupTarget(.emptyPage)

        #expect(updated.startupTarget == .emptyPage)
        #expect(updated.url == config.url)
    }

    // MARK: - #15: disabled built-in scripts

    @Test func disabledBuiltInScriptIDsIsEmptyWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.disabledBuiltInScriptIDs.isEmpty)
    }

    @Test func parsesDisabledBuiltInScriptIDsWhenPresent() throws {
        let toml = """
        url = "https://example.com"
        disabled_built_in_scripts = ["generic-video-focus"]
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.disabledBuiltInScriptIDs == ["generic-video-focus"])
    }

    @Test func serializingThenReparsingRoundTripsDisabledBuiltInScriptIDs() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!, disabledBuiltInScriptIDs: ["a", "b"])

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func updatingDisabledBuiltInScriptIDsReturnsCopyWithNewSetOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        let updated = config.updatingDisabledBuiltInScriptIDs(["x"])

        #expect(updated.disabledBuiltInScriptIDs == ["x"])
        #expect(updated.url == config.url)
    }

    // MARK: - updating* helpers not yet covered above

    @Test func updatingGhostOpacityReturnsCopyWithNewOpacityOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        let updated = config.updatingGhostOpacity(0.9)

        #expect(updated.ghostOpacity == 0.9)
        #expect(updated.url == config.url)
    }

    @Test func updatingCustomScriptReturnsCopyWithNewScriptOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        let updated = config.updatingCustomScript("console.log(1)")

        #expect(updated.customScript == "console.log(1)")
        #expect(updated.url == config.url)
    }

    @Test func updatingHotkeyMappingsReturnsCopyWithNewMappingsOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 1, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 2, modifierFlags: 0))

        let updated = config.updatingHotkeyMappings([mapping])

        #expect(updated.hotkeyMappings == [mapping])
        #expect(updated.url == config.url)
    }
}
