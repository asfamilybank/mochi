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

    // #73: custom stylesheet — third Script Injection source.

    @Test func customStylesheetIsNilWhenAbsentAndNotSerialized() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.customStylesheet == nil)
        #expect(!config.serialized().contains("custom_stylesheet"))
    }

    @Test func serializingThenReparsingRoundTripsCustomStylesheet() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!)
            .updatingCustomStylesheet("body { color: red; }\n/* \"q\" */")

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
        #expect(reparsed.customStylesheet == "body { color: red; }\n/* \"q\" */")
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

    @Test func aLeftoverMouseAvoidanceKeyIsIgnoredAndDroppedOnSave() throws {
        // Mouse-entered avoidance was removed (ADR-0019); config files written before that still
        // carry its key and must keep loading.
        let toml = """
        url = "https://example.com"
        mouse_avoidance_enabled = false
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config == WidgetConfig(url: URL(string: "https://example.com")!))
        #expect(!config.serialized().contains("mouse_avoidance_enabled"))
    }

    @Test func snapDefaultsToEnabledWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.isSnapEnabled == true)
    }

    @Test func parsesSnapEnabledWhenPresent() throws {
        let toml = """
        url = "https://example.com"
        snap_enabled = false
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.isSnapEnabled == false)
    }

    @Test func serializingThenReparsingRoundTripsSnapEnabled() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: false)

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func ignoresALeftOverSnapThresholdKeyInsteadOfThrowing() throws {
        // The threshold stopped being configurable (ADR-0012) — a knob whose effect nobody can
        // judge. As with `pinned`, no migration: unknown keys are ignored on load and dropped on
        // the next write.
        let toml = """
        url = "https://example.com"
        snap_threshold = 24.0
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.url == URL(string: "https://example.com")!)
        #expect(!config.serialized().contains("snap_threshold"))
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

    // #45: the action-hotkey override table

    @Test func hotkeyOverridesIsEmptyWhenAbsentSoBothActionsUseTheirDefaults() throws {
        let config = try WidgetConfig.parse("")

        #expect(config.hotkeyOverrides.isEmpty)
        #expect(config.hotkey(for: .toggleGhostMode) == DefaultHotkeys.toggleGhostMode)
        #expect(config.hotkey(for: .hideWidget) == DefaultHotkeys.hideWidget)
    }

    @Test func parsesAHotkeyOverrideWhenPresent() throws {
        let toml = """
        [hotkeys.toggle_ghost_mode]
        key_code = 17
        modifiers = 2304
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkey(for: .toggleGhostMode) == Hotkey(keyCode: 17, modifierFlags: 2304))
        #expect(config.hotkey(for: .hideWidget) == DefaultHotkeys.hideWidget)
    }

    @Test func skipsAMalformedHotkeyOverrideAndKeepsTheOthers() throws {
        let toml = """
        [hotkeys.toggle_ghost_mode]
        key_code = -1
        modifiers = 2304

        [hotkeys.hide_widget]
        key_code = 11
        modifiers = 2304
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkey(for: .toggleGhostMode) == DefaultHotkeys.toggleGhostMode)
        #expect(config.hotkey(for: .hideWidget) == Hotkey(keyCode: 11, modifierFlags: 2304))
    }

    @Test func ignoresAnUnknownHotkeyActionIdentifierInsteadOfThrowing() throws {
        let toml = """
        [hotkeys.summon_toolbar]
        key_code = 17
        modifiers = 2304
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkeyOverrides.isEmpty)
    }

    @Test func serializingThenReparsingRoundTripsHotkeyOverrides() throws {
        let original = WidgetConfig(
            hotkeyOverrides: [
                .toggleGhostMode: Hotkey(keyCode: 17, modifierFlags: 2304),
                .hideWidget: Hotkey(keyCode: 11, modifierFlags: 4352),
            ])

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func updatingAHotkeyOverrideToTheDefaultRemovesTheEntry() {
        let config = WidgetConfig(hotkeyOverrides: [.toggleGhostMode: Hotkey(keyCode: 17, modifierFlags: 2304)])

        let updated = config.updatingHotkeyOverride(.toggleGhostMode, to: DefaultHotkeys.toggleGhostMode)

        #expect(updated.hotkeyOverrides.isEmpty)
        #expect(updated.serialized().contains("hotkeys") == false)
    }

    @Test func updatingAHotkeyOverrideToANonDefaultStoresIt() {
        let config = WidgetConfig()
        let custom = Hotkey(keyCode: 17, modifierFlags: 2304)

        let updated = config.updatingHotkeyOverride(.hideWidget, to: custom)

        #expect(updated.hotkeyOverrides == [.hideWidget: custom])
        #expect(updated.hotkey(for: .hideWidget) == custom)
    }

    // #85: an action hotkey can be cleared — the user takes the combo back from Mochi.

    @Test func aClearedActionHotkeyIsWrittenAsUnboundAndReadsBackAsNoHotkey() throws {
        let cleared = WidgetConfig().updatingHotkeyOverride(.hideWidget, to: nil)

        #expect(cleared.hotkey(for: .hideWidget) == nil)
        #expect(cleared.hotkey(for: .toggleGhostMode) == DefaultHotkeys.toggleGhostMode)
        let reparsed = try WidgetConfig.parse(cleared.serialized())
        #expect(reparsed == cleared)
        #expect(reparsed.hotkey(for: .hideWidget) == nil)
    }

    @Test func parsesAnUnboundActionHotkey() throws {
        let toml = """
        [hotkeys.toggle_ghost_mode]
        kind = "unbound"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkey(for: .toggleGhostMode) == nil)
        #expect(config.hotkey(for: .hideWidget) == DefaultHotkeys.hideWidget)
    }

    /// Files written before #85 have no `kind` — a bare key code + modifiers is still a rebinding.
    @Test func anEntryWithoutAKindIsStillARebinding() throws {
        let toml = """
        [hotkeys.hide_widget]
        key_code = 11
        modifiers = 2304
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkey(for: .hideWidget) == Hotkey(keyCode: 11, modifierFlags: 2304))
    }

    @Test func clearingAndThenRestoringTheDefaultLeavesNoHotkeysTable() {
        let restored = WidgetConfig()
            .updatingHotkeyOverride(.toggleGhostMode, to: nil)
            .updatingHotkeyOverride(.toggleGhostMode, to: DefaultHotkeys.toggleGhostMode)

        #expect(restored.hotkeyOverrides.isEmpty)
        #expect(restored.serialized().contains("hotkeys") == false)
    }

    /// #58: moving the defaults to ⌥G/⌥H needs no migration because the config only stores
    /// overrides — a user who customised either action (here: pinned the old ⌥⌘G/⌥⌘H combos
    /// by hand) keeps exactly what they chose after upgrading.
    @Test func aStoredOverrideStillWinsOverTheNewOptionOnlyDefaults() throws {
        let toml = """
        [hotkeys.toggle_ghost_mode]
        key_code = 5
        modifiers = 2304

        [hotkeys.hide_widget]
        key_code = 4
        modifiers = 2304
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkey(for: .toggleGhostMode) == Hotkey(keyCode: 0x05, modifierFlags: 0x0100 | 0x0800))
        #expect(config.hotkey(for: .hideWidget) == Hotkey(keyCode: 0x04, modifierFlags: 0x0100 | 0x0800))
        #expect(config.hotkey(for: .toggleGhostMode) != DefaultHotkeys.toggleGhostMode)
        #expect(config.hotkey(for: .hideWidget) != DefaultHotkeys.hideWidget)
        #expect(try WidgetConfig.parse(config.serialized()) == config)
    }

    @Test func updatingSnapReturnsACopyWithOnlyThatFieldChanged() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        let snapOff = config.updatingSnapEnabled(false)

        #expect(snapOff.isSnapEnabled == false && snapOff.url == config.url)
    }

    // #70: autoplay policy and minimum font size.

    @Test func autoplayAndMinimumFontSizeDefaultWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.autoplayPolicy == .allowAll)
        #expect(config.minimumFontSize == nil)
    }

    @Test(arguments: [
        (raw: "allow_all", expected: WidgetConfig.AutoplayPolicy.allowAll),
        (raw: "stop_media_with_sound", expected: .stopMediaWithSound),
        (raw: "never", expected: .never),
        (raw: "bogus", expected: .allowAll),
    ])
    func parsesAutoplayPolicyFallingBackToDefault(_ row: (raw: String, expected: WidgetConfig.AutoplayPolicy)) throws {
        let config = try WidgetConfig.parse("autoplay = \"\(row.raw)\"")
        #expect(config.autoplayPolicy == row.expected)
    }

    @Test(arguments: [
        (raw: "14", expected: Optional(14)),
        (raw: "9", expected: 9),
        (raw: "13", expected: nil),
        (raw: "-1", expected: nil),
        (raw: "\"big\"", expected: nil),
    ])
    func parsesMinimumFontSizeOnlyFromTheOfferedSizes(_ row: (raw: String, expected: Int?)) throws {
        let config = try WidgetConfig.parse("minimum_font_size = \(row.raw)")
        #expect(config.minimumFontSize == row.expected)
    }

    @Test func serializingThenReparsingRoundTripsAutoplayAndMinimumFontSize() throws {
        var original = WidgetConfig(url: URL(string: "https://example.com")!)
        original.autoplayPolicy = .never
        original.minimumFontSize = 18

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
        #expect(!WidgetConfig().serialized().contains("minimum_font_size"))
    }

    // MARK: - #69: 摄像头 / 麦克风

    @Test func mediaCapturePermissionsDefaultToAskWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.cameraPermission == .ask)
        #expect(config.microphonePermission == .ask)
        #expect(WidgetConfig().cameraPermission == .ask && WidgetConfig().microphonePermission == .ask)
    }

    @Test(arguments: [
        (raw: "\"ask\"", expected: WidgetConfig.MediaCapturePermission.ask),
        (raw: "\"deny\"", expected: .deny),
        (raw: "\"allow\"", expected: .allow),
        (raw: "\"bogus\"", expected: .ask),
        (raw: "\"Allow\"", expected: .ask),
        (raw: "true", expected: .ask),
        (raw: "1", expected: .ask),
    ])
    func parsesMediaCapturePermissionsFallingBackToAsk(_ row: (raw: String, expected: WidgetConfig.MediaCapturePermission)) throws {
        let camera = try WidgetConfig.parse("camera_permission = \(row.raw)")
        let microphone = try WidgetConfig.parse("microphone_permission = \(row.raw)")
        #expect(camera.cameraPermission == row.expected && camera.microphonePermission == .ask)
        #expect(microphone.microphonePermission == row.expected && microphone.cameraPermission == .ask)
    }

    @Test func serializingThenReparsingRoundTripsMediaCapturePermissions() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!)
            .updatingCameraPermission(.deny)
            .updatingMicrophonePermission(.allow)

        #expect(original.cameraPermission == .deny && original.microphonePermission == .allow)
        #expect(try WidgetConfig.parse(original.serialized()) == original)
    }

    // MARK: - #72: 高级 pane switches

    @Test func advancedSwitchesDefaultToOffWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.isHTTPWarningEnabled == false)
        #expect(config.isWebInspectorEnabled == false)
    }

    @Test func parsesAdvancedSwitchesWhenPresent() throws {
        let config = try WidgetConfig.parse("""
            url = "https://example.com"
            http_warning_enabled = true
            web_inspector_enabled = true
            """)
        #expect(config.isHTTPWarningEnabled == true)
        #expect(config.isWebInspectorEnabled == true)
    }

    @Test func invalidAdvancedSwitchValuesFallBackToOff() throws {
        let config = try WidgetConfig.parse("""
            url = "https://example.com"
            http_warning_enabled = "yes"
            web_inspector_enabled = 1
            """)
        #expect(config.isHTTPWarningEnabled == false)
        #expect(config.isWebInspectorEnabled == false)
    }

    @Test func serializingThenReparsingRoundTripsAdvancedSwitches() throws {
        let original = WidgetConfig(url: URL(string: "https://example.com")!)
            .updatingHTTPWarningEnabled(true)
            .updatingWebInspectorEnabled(true)
        #expect(try WidgetConfig.parse(original.serialized()) == original)
    }
}

@Suite struct WidgetConfigSearchEngineTests {
    @Test func defaultsToGoogleWhenAbsent() throws {
        #expect(try WidgetConfig.parse("").searchEngine == .google)
        #expect(WidgetConfig().searchEngine == .google)
    }

    @Test(arguments: [
        (raw: "google", expected: SearchEngine.google),
        (raw: "bing", expected: SearchEngine.bing),
        (raw: "duckduckgo", expected: SearchEngine.duckDuckGo),
        (raw: "baidu", expected: SearchEngine.baidu),
        (raw: "yahoo", expected: SearchEngine.google),
    ])
    func parsesSearchEngineFallingBackToGoogle(_ row: (raw: String, expected: SearchEngine)) throws {
        #expect(try WidgetConfig.parse("search_engine = '\(row.raw)'").searchEngine == row.expected)
    }

    @Test func nonStringValueFallsBackToGoogle() throws {
        #expect(try WidgetConfig.parse("search_engine = 3").searchEngine == .google)
    }

    @Test(arguments: SearchEngine.allCases)
    func roundTripsEveryEngine(_ engine: SearchEngine) throws {
        let config = WidgetConfig().updatingSearchEngine(engine)
        #expect(try WidgetConfig.parse(config.serialized()).searchEngine == engine)
    }

    @Test func updatingSearchEngineChangesOnlyThatField() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: false)
        let updated = config.updatingSearchEngine(.baidu)
        #expect(updated.searchEngine == .baidu)
        #expect(updated.url == config.url && updated.isSnapEnabled == false)
    }
}

/// #68: 文件下载位置.
@Suite struct WidgetConfigDownloadLocationTests {
    @Test func defaultsToDownloadsFolderWhenAbsent() throws {
        #expect(try WidgetConfig.parse("").downloadLocation == .downloadsFolder)
        #expect(WidgetConfig().downloadLocation == .downloadsFolder)
    }

    @Test(arguments: [
        (toml: "download_location = 'downloads'", expected: DownloadLocation.downloadsFolder),
        (toml: "download_location = 'ask'", expected: .askEachTime),
        (toml: "download_location = 'folder'\ndownload_folder = '/Volumes/外置/下载'",
            expected: .folder(URL(fileURLWithPath: "/Volumes/外置/下载", isDirectory: true))),
        // Invalid values fall back to 下载.
        (toml: "download_location = 'desktop'", expected: .downloadsFolder),
        (toml: "download_location = 3", expected: .downloadsFolder),
        (toml: "download_location = 'folder'", expected: .downloadsFolder),
        (toml: "download_location = 'folder'\ndownload_folder = 'relative/path'", expected: .downloadsFolder),
        (toml: "download_location = 'folder'\ndownload_folder = 7", expected: .downloadsFolder),
        // A folder path left over in the file doesn't matter unless 其他… is selected.
        (toml: "download_location = 'ask'\ndownload_folder = '/tmp/x'", expected: .askEachTime),
    ])
    func parsesDownloadLocationLeniently(_ row: (toml: String, expected: DownloadLocation)) throws {
        #expect(try WidgetConfig.parse(row.toml).downloadLocation == row.expected)
    }

    @Test func expandsTildeInAHandEditedFolder() throws {
        let config = try WidgetConfig.parse("download_location = 'folder'\ndownload_folder = '~/Stuff'")
        let expected = URL(fileURLWithPath: ("~/Stuff" as NSString).expandingTildeInPath, isDirectory: true)
        #expect(config.downloadLocation == .folder(expected))
    }

    @Test(arguments: [
        DownloadLocation.downloadsFolder, .askEachTime,
        .folder(URL(fileURLWithPath: "/Users/someone/My Files", isDirectory: true)),
    ])
    func roundTripsEveryLocation(_ location: DownloadLocation) throws {
        let config = WidgetConfig().updatingDownloadLocation(location)
        #expect(try WidgetConfig.parse(config.serialized()).downloadLocation == location)
    }

    @Test func defaultIsNotWritten() {
        let toml = WidgetConfig().serialized()
        #expect(!toml.contains("download_location"))
        #expect(!toml.contains("download_folder"))
    }

    @Test func folderPathIsWrittenOnlyForTheFolderKind() {
        #expect(!WidgetConfig().updatingDownloadLocation(.askEachTime).serialized().contains("download_folder"))
        let folder = WidgetConfig().updatingDownloadLocation(.folder(URL(fileURLWithPath: "/a/b", isDirectory: true)))
        #expect(folder.serialized().contains("download_folder = '/a/b'"))
    }

    @Test func updatingDownloadLocationChangesOnlyThatField() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: false)
        let updated = config.updatingDownloadLocation(.askEachTime)
        #expect(updated.downloadLocation == .askEachTime)
    }
}

/// 网页内容 → 弹出式窗口 (#67).
@Suite struct WidgetConfigPopupWindowPolicyTests {
    @Test func defaultsToBlockWhenAbsent() throws {
        #expect(try WidgetConfig.parse("").popupWindowPolicy == .block)
        #expect(WidgetConfig().popupWindowPolicy == .block)
    }

    @Test(arguments: [
        (raw: "'allow'", expected: WidgetConfig.PopupWindowPolicy.allow),
        (raw: "'block'", expected: .block),
        (raw: "'sometimes'", expected: .block),
        (raw: "true", expected: .block),
    ])
    func parsesPolicyFallingBackToBlock(_ row: (raw: String, expected: WidgetConfig.PopupWindowPolicy)) throws {
        #expect(try WidgetConfig.parse("popup_windows = \(row.raw)").popupWindowPolicy == row.expected)
    }

    @Test(arguments: WidgetConfig.PopupWindowPolicy.allCases)
    func roundTripsEveryPolicy(_ policy: WidgetConfig.PopupWindowPolicy) throws {
        let config = WidgetConfig(url: URL(string: "https://example.com")!).updatingPopupWindowPolicy(policy)
        #expect(try WidgetConfig.parse(config.serialized()) == config)
    }

    @Test func onlyADepartureFromTheDefaultIsWritten() {
        #expect(!WidgetConfig().serialized().contains("popup_windows"))
        #expect(WidgetConfig().updatingPopupWindowPolicy(.allow).serialized().contains("popup_windows"))
    }

    @Test func updatingPolicyChangesOnlyThatField() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: false)
        let updated = config.updatingPopupWindowPolicy(.allow)
        #expect(updated.popupWindowPolicy == .allow)
        #expect(updated.url == config.url && updated.isSnapEnabled == false)
    }
    // MARK: 视频控制 (#78)

    @Test func aConfigWithoutVideoControlUsesTheDefaults() throws {
        let config = try WidgetConfig.parse("ghost_opacity = 0.3")

        #expect(config.videoControlTrigger(for: .togglePlayback) == .modifierTap(.rightOption))
        #expect(config.videoControlTrigger(for: .seekBackward) == .modifierTap(.rightCommand))
        #expect(config.videoControlTrigger(for: .seekForward) == nil)
        #expect(config.videoSeekStep == 5)
    }

    /// #89 only stops the settings from recording a combo with no ⌃/⌥/⌘; one saved before that
    /// rule keeps loading — and keeps being written back — unchanged.
    @Test func aBareKeyBindingSavedBeforeTheModifierRuleStillLoadsAndRoundTrips() throws {
        let toml = """
        [hotkeys.hide_widget]
        key_code = 38
        modifiers = 0

        [video_control.seek_forward]
        kind = "keystroke"
        key_code = 37
        modifiers = 512

        [[hotkey_mappings]]
        trigger_key_code = 40
        trigger_modifiers = 0
        page_key_code = 49
        page_modifiers = 0
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.hotkey(for: .hideWidget) == Hotkey(keyCode: 38, modifierFlags: 0))
        #expect(config.videoControlTrigger(for: .seekForward) == .keystroke(Hotkey(keyCode: 37, modifierFlags: 512)))
        #expect(config.hotkeyMappings.map(\.trigger) == [Hotkey(keyCode: 40, modifierFlags: 0)])
        #expect(try WidgetConfig.parse(config.serialized()) == config)
    }

    @Test func aDoubleTapVideoKeyRoundTrips() throws {
        let config = WidgetConfig().updatingTriggerKey(.modifierDoubleTap(.leftControl), for: .seekForward)

        let reparsed = try WidgetConfig.parse(config.serialized())

        #expect(reparsed.videoControlTrigger(for: .seekForward) == .modifierDoubleTap(.leftControl))
        #expect(config.serialized().contains("modifier_double_tap"))
    }

    @Test func parsesEveryKindOfVideoControlBinding() throws {
        let toml = """
        [video_control]
        seek_step = 10

        [video_control.toggle_playback]
        kind = "keystroke"
        key_code = 50
        modifiers = 0

        [video_control.seek_backward]
        kind = "unbound"

        [video_control.seek_forward]
        kind = "modifier_tap"
        modifier = "right_shift"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.videoControlTrigger(for: .togglePlayback) == .keystroke(Hotkey(keyCode: 50, modifierFlags: 0)))
        #expect(config.videoControlTrigger(for: .seekBackward) == nil)
        #expect(config.videoControlTrigger(for: .seekForward) == .modifierTap(.rightShift))
        #expect(config.videoSeekStep == 10)
    }

    @Test func aMalformedVideoControlBindingFallsBackToTheDefault() throws {
        let toml = """
        [video_control.toggle_playback]
        kind = "modifier_tap"
        modifier = "middle_option"

        [video_control.seek_backward]
        kind = "keystroke"
        key_code = -3
        modifiers = 0

        [video_control.seek_forward]
        kind = "chord"

        [video_control.zoom_video]
        kind = "unbound"
        """

        let config = try WidgetConfig.parse(toml)

        #expect(config.videoControlOverrides.isEmpty)
        #expect(config.videoControlTrigger(for: .togglePlayback) == .modifierTap(.rightOption))
    }

    @Test(arguments: [
        (raw: "0", expected: 1),
        (raw: "-4", expected: 1),
        (raw: "60", expected: 60),
        (raw: "300", expected: 60),
        (raw: "2.5", expected: 5),
        (raw: "\"ten\"", expected: 5),
    ])
    func clampsTheSeekStepIntoOneToSixtySeconds(_ testCase: (raw: String, expected: Int)) throws {
        let config = try WidgetConfig.parse("[video_control]\nseek_step = \(testCase.raw)")

        #expect(config.videoSeekStep == testCase.expected)
    }

    @Test func serializingThenReparsingRoundTripsVideoControl() throws {
        let original = WidgetConfig()
            .updatingTriggerKey(.keystroke(Hotkey(keyCode: 0x26, modifierFlags: 0x0800)), for: .togglePlayback)
            .updatingTriggerKey(nil, for: .seekBackward)
            .updatingTriggerKey(.modifierTap(.leftControl), for: .seekForward)
            .updatingVideoSeekStep(15)

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
        #expect(reparsed.videoControlTrigger(for: .seekBackward) == nil)
    }

    @Test func clearingADefaultBoundActionIsRememberedAcrossARestart() throws {
        let cleared = WidgetConfig().updatingTriggerKey(nil, for: .togglePlayback)

        let reparsed = try WidgetConfig.parse(cleared.serialized())

        #expect(reparsed.videoControlTrigger(for: .togglePlayback) == nil)
    }

    @Test func bindingAnActionBackToItsDefaultLeavesNothingInTheFile() {
        let config = WidgetConfig()
            .updatingTriggerKey(.modifierTap(.leftOption), for: .togglePlayback)
            .updatingTriggerKey(.modifierTap(.rightOption), for: .togglePlayback)
            .updatingTriggerKey(nil, for: .seekForward)

        #expect(config.videoControlOverrides.isEmpty)
        #expect(config.serialized().contains("video_control") == false)
    }

    @Test func updatingTheSeekStepClampsIt() {
        #expect(WidgetConfig().updatingVideoSeekStep(0).videoSeekStep == 1)
        #expect(WidgetConfig().updatingVideoSeekStep(61).videoSeekStep == 60)
    }
}
