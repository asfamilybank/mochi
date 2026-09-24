import Foundation
import Testing

@testable import MochiCore

/// The observable shape of one Ghost Mode entry — plain `Equatable` arrays rather than the
/// `FakePlatformOps` tuple-arrays it's built from, which aren't `Equatable` themselves (per
/// `FakePlatformOps`'s own doc comment on labeled-tuple arrays).
private struct GhostModeEntrySignature: Equatable {
    let passthrough: [Bool]
    let opacity: [Double]
    let pinned: [Bool]
}

/// The four states the tray's mode entries (#63) have to reflect.
enum TrayScenario: Sendable {
    case noWidget, normal, ghost, ghostHidden
}

@Suite struct OrchestratorTests {
    @Test func startsWidgetWindowUsingPersistedFrameAndLoadsConfiguredURL() {
        let fake = FakePlatformOps()
        fake.stubbedScreens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let persistedFrame = WindowFrame(x: 50, y: 50, width: 800, height: 600)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: persistedFrame, zoom: 1.5)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.createdFrames == [persistedFrame])
        #expect(fake.loadedURLs.map(\.url) == [config.url!])
        #expect(fake.appliedZooms.map(\.zoom) == [1.5])
        #expect(fake.shownWindowIDs == [1])
    }

    // #16: startup content resolution

    @Test func showsEmptyPageContentInsteadOfLoadingWhenThereIsNoURLOrStartupTarget() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: nil)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.emptyPageShownWindowIDs == [1])
        #expect(fake.loadedURLs.isEmpty)
    }

    @Test func loadsAFixedStartupURLOverridingTheLastVisitedURL() {
        let fake = FakePlatformOps()
        let fixedStartupURL = URL(string: "https://fixed-startup.example.com")!
        let config = WidgetConfig(url: URL(string: "https://last-visited.example.com")!, startupTarget: .url(fixedStartupURL))
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.loadedURLs.map(\.url) == [fixedStartupURL])
        #expect(fake.emptyPageShownWindowIDs.isEmpty)
    }

    @Test func showsEmptyPageContentWhenExplicitlyChosenAsStartupTargetEvenWithALastVisitedURL() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://last-visited.example.com")!, startupTarget: .emptyPage)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.emptyPageShownWindowIDs == [1])
        #expect(fake.loadedURLs.isEmpty)
    }

    @Test func fallsBackToSafeDefaultFrameWhenPersistedFrameIsOffscreen() {
        let fake = FakePlatformOps()
        let primaryScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        fake.stubbedScreens = [primaryScreen]
        let offscreenFrame = WindowFrame(x: 10_000, y: 10_000, width: 800, height: 600)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: offscreenFrame, zoom: 1.0)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.createdFrames == [WindowPlacement.safeDefault(in: primaryScreen)])
    }

    @Test func doesNotApplyZoomWhenNoWindowStateIsPersisted() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.appliedZooms.isEmpty)
    }

    @Test func persistsCapturedWindowStateWhenWindowWillClose() {
        let fake = FakePlatformOps()
        fake.stubbedCapturedWindowState = WindowState(
            frame: WindowFrame(x: 10, y: 20, width: 900, height: 700), zoom: 1.25)
        var persisted: WindowState?
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }) { state in
            persisted = state
        }

        orchestrator.start()
        fake.simulateWindowWillClose()

        #expect(persisted == fake.stubbedCapturedWindowState)
    }

    @Test func persistCurrentWindowStateCanBeTriggeredExplicitlyOnAppTermination() {
        let fake = FakePlatformOps()
        fake.stubbedCapturedWindowState = WindowState(
            frame: WindowFrame(x: 5, y: 6, width: 700, height: 500), zoom: 0.8)
        var persisted: WindowState?
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }) { state in
            persisted = state
        }

        orchestrator.start()
        orchestrator.persistCurrentWindowState()

        #expect(persisted == fake.stubbedCapturedWindowState)
    }

    @Test func showsToolbarOnStartThroughPlatformOpsRatherThanDirectWindowAccess() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.toolbarVisibilityChanges.map(\.visible) == [true])
        #expect(fake.toolbarVisibilityChanges.map(\.windowID) == [1])
    }

    @Test func submittingURLFromAddressBarLoadsItAndPersistsItOverConfiguredURL() {
        let fake = FakePlatformOps()
        var persistedURL: URL?
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, persistURL: { url in
            persistedURL = url
        })
        orchestrator.start()

        let navigatedURL = URL(string: "https://example.org")!
        fake.simulateURLSubmitted(navigatedURL)

        #expect(fake.loadedURLs.map(\.url) == [config.url!, navigatedURL])
        #expect(persistedURL == navigatedURL)
    }

    @Test func injectsBuiltInScriptsThroughPlatformOpsWhenNavigationFinishes() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.map(\.source) == BuiltInScripts.all.map(\.source))
    }

    @Test func injectsConfiguredCustomScriptThroughPlatformOpsWhenNavigationFinishes() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, customScript: "console.log('hi')")
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.map(\.source).last == "console.log('hi')")
    }

    @Test func doesNotInjectACustomScriptWhenNoneIsConfigured() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.count == BuiltInScripts.all.count)
    }

    @Test func skipsInjectingABuiltInScriptDisabledInSettings() {
        let fake = FakePlatformOps()
        let disabledID = BuiltInScripts.all[0].id
        let config = WidgetConfig(url: URL(string: "https://example.com")!, disabledBuiltInScriptIDs: [disabledID])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateNavigationFinished()

        #expect(!fake.injectedScripts.map(\.source).contains(BuiltInScripts.all[0].source))
        #expect(fake.injectedScripts.count == BuiltInScripts.all.count - 1)
    }

    @Test func registersBothActionHotkeysOnStartInAFixedOrder() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(
            fake.registeredHotkeys == [
                DefaultHotkeys.toggleGhostMode,
                DefaultHotkeys.hideWidget,
            ])
    }

    @Test func presentsAnAlertWhenHotkeyRegistrationFailsInsteadOfFailingSilently() {
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func doesNotPresentAnAlertWhenHotkeyRegistrationSucceeds() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func pressingTheGlobalHotkeyTogglesGhostModeThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateHotkeyPressed()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
    }

    @Test(arguments: [true, false])
    func appliesTheConfiguredSnapPreferenceOnStartThroughPlatformOps(_ enabled: Bool) {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: enabled)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.snapEnabledChanges.map(\.enabled) == [enabled])
        #expect(fake.snapEnabledChanges.map(\.windowID) == [1])
    }

    // #63: the tray menu, regrouped after Bob — icons, checkmarks, live hints, per-state greying.

    @Test func createsTheTrayMenuWithItsEntriesSeparatorsAndIconsInOrderOnStart() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.trayMenuItems.map { $0.isSeparator ? "—" : $0.title }
            == ["打开窗口", "幽灵模式", "隐藏窗口", "—", "设置…", "关于 Mochi", "—", "退出"])
        #expect(fake.trayMenuItems.map(\.icon) == [
            .symbol(DesignTokens.Symbol.openWidget), .ghost, .symbol(DesignTokens.Symbol.hideWidget), nil,
            .symbol(DesignTokens.Symbol.settings), .symbol(DesignTokens.Symbol.about), nil, .appQuit,
        ])
    }

    @Test func trayHintsShowTheEffectiveHotkeysAndTheFixedMenuShortcuts() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        #expect(fake.trayMenuItems.map { $0.hotkeyHint() } == [
            nil, DefaultHotkeys.toggleGhostMode, DefaultHotkeys.hideWidget, nil,
            DefaultHotkeys.openSettings, nil, nil, DefaultHotkeys.quit,
        ])
    }

    /// The tray is built once, so a hint has to be read from the config each time the menu opens:
    /// a rebind in the settings panel shows up on the very next open, with no second tray.
    @Test func trayHintsFollowARebindWithoutRebuildingTheTray() {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        let reboundToggle = Hotkey(keyCode: 0x0E, modifierFlags: 0x0800 | 0x0200)  // ⌥⇧E
        let reboundHide = Hotkey(keyCode: 0x1F, modifierFlags: 0x1000)  // ⌃O

        config = config
            .updatingHotkeyOverride(.toggleGhostMode, to: reboundToggle)
            .updatingHotkeyOverride(.hideWidget, to: reboundHide)

        #expect(fake.trayItem("幽灵模式").hotkeyHint() == reboundToggle)
        #expect(fake.trayItem("隐藏窗口").hotkeyHint() == reboundHide)
        #expect(fake.createTrayIconCallCount == 1)
    }

    @Test(arguments: [
        (scenario: TrayScenario.noWidget, ghostChecked: false, ghostEnabled: false, hideChecked: false, hideEnabled: false),
        (scenario: .normal, ghostChecked: false, ghostEnabled: true, hideChecked: false, hideEnabled: false),
        (scenario: .ghost, ghostChecked: true, ghostEnabled: true, hideChecked: false, hideEnabled: true),
        (scenario: .ghostHidden, ghostChecked: true, ghostEnabled: true, hideChecked: true, hideEnabled: true),
    ])
    func trayModeEntriesReflectTheCurrentState(
        _ row: (scenario: TrayScenario, ghostChecked: Bool, ghostEnabled: Bool, hideChecked: Bool, hideEnabled: Bool)
    ) {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        switch row.scenario {
        case .noWidget:
            orchestrator.closeWidget()
        case .normal:
            break
        case .ghost:
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        case .ghostHidden:
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
            fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        }

        let ghost = fake.trayItem("幽灵模式")
        let hide = fake.trayItem("隐藏窗口")
        #expect(ghost.isChecked() == row.ghostChecked)
        #expect(ghost.isEnabled() == row.ghostEnabled)
        #expect(hide.isChecked() == row.hideChecked)
        #expect(hide.isEnabled() == row.hideEnabled)
        // Everything else is always on offer, and nothing else is ever checked.
        for item in fake.trayMenuItems where !item.isSeparator && item.title != "幽灵模式" && item.title != "隐藏窗口" {
            #expect(item.isEnabled())
            #expect(!item.isChecked())
        }
    }

    @Test func trayGhostModeEntryEntersGhostModeFromNormalMode() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayItem("幽灵模式").action()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
    }

    /// The tray is the one control that is always reachable, so it must get the widget back even
    /// when Ghost Mode has left it fully hidden and click-through.
    @Test func trayGhostModeEntryExitsGhostModeEvenWhileFullyHiddenAndClickThrough() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        fake.trayItem("幽灵模式").action()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
        #expect(!fake.trayItem("幽灵模式").isChecked())
        #expect(!fake.trayItem("隐藏窗口").isChecked())
    }

    @Test func trayHideEntryTogglesHiddenInGhostMode() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        fake.trayItem("隐藏窗口").action()
        #expect(fake.trayItem("隐藏窗口").isChecked())
        fake.trayItem("隐藏窗口").action()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.2])
        #expect(!fake.trayItem("隐藏窗口").isChecked())
    }

    @Test func trayModeEntriesDoNothingWithoutAWidget() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        orchestrator.closeWidget()

        fake.trayItem("幽灵模式").action()
        fake.trayItem("隐藏窗口").action()

        #expect(fake.mousePassthroughChanges.isEmpty)
        #expect(fake.contentOpacityChanges.isEmpty)
        #expect(!orchestrator.hasActiveWidget)
    }

    /// The tray's 关于 Mochi is the App menu's About (#62) — the same panel, then activation, so
    /// from Ghost Mode the panel becomes key and the widget is left alone.
    @Test func trayAboutEntryOpensTheAboutPanelLikeTheAppMenu() {
        let fake = FakePlatformOps()
        var aboutCallCount = 0
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, openAbout: { aboutCallCount += 1 })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        let shownBefore = fake.shownWindowIDs

        fake.trayItem("关于 Mochi").action()

        #expect(aboutCallCount == 1)
        #expect(fake.activateAppCallCount == 1)
        #expect(fake.shownWindowIDs == shownBefore)
        #expect(fake.trayItem("幽灵模式").isChecked())
    }

    // #44: the toolbar's Ghost Mode button must converge on the exact same entry point as the
    // default hotkey and the tray icon — no simplified path of its own.

    @Test func toolbarButtonEntersGhostModeIdenticallyToTheHotkeyAndTheTray() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.4)

        func captureEntrySignature(_ trigger: (FakePlatformOps) -> Void) -> GhostModeEntrySignature {
            let fake = FakePlatformOps()
            let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
            orchestrator.start()
            trigger(fake)
            return GhostModeEntrySignature(
                passthrough: fake.mousePassthroughChanges.map(\.enabled),
                opacity: fake.contentOpacityChanges.map(\.opacity),
                pinned: fake.pinnedChanges.map(\.pinned)
            )
        }

        let viaButton = captureEntrySignature { $0.simulateGhostModeToggleRequested() }
        let viaHotkey = captureEntrySignature { $0.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode) }
        let viaTray = captureEntrySignature { $0.trayItem("幽灵模式").action() }

        #expect(viaButton == viaHotkey)
        #expect(viaButton == viaTray)
    }

    @Test func toolbarButtonTogglesBackToNormalModeWhenAlreadyInGhostModeLikeTheHotkey() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.4)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateGhostModeToggleRequested()

        fake.simulateGhostModeToggleRequested()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.4, 1.0])
        #expect(fake.pinnedChanges.map(\.pinned) == [true, false])
    }

    @Test func toolbarButtonGivesUpFocusOnEnteringGhostModeThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateGhostModeToggleRequested()

        #expect(fake.deactivateAppCallCount == 1)
    }

    @Test func theHotkeyAndTrayGhostModeEntriesDoNotGiveUpFocus() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.trayItem("幽灵模式").action()

        #expect(fake.deactivateAppCallCount == 0)
    }

    @Test func trayOpenSettingsEntryInvokesTheInjectedCallback() {
        let fake = FakePlatformOps()
        var openSettingsCallCount = 0
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, openSettings: {
            openSettingsCallCount += 1
        })
        orchestrator.start()

        fake.trayItem("设置…").action()

        #expect(openSettingsCallCount == 1)
    }

    @Test func trayQuitEntryTerminatesTheAppThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayItem("退出").action()

        #expect(fake.terminateAppCallCount == 1)
    }

    // #37: reload/zoom/settings are public operations the main menu calls directly — no longer
    // reachable via a global hotkey (see `registersAllDefaultHotkeysOnStartInAFixedOrder`).

    @Test func callingReloadPageReloadsThePageThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.reloadPage()

        #expect(fake.reloadedWindowIDs == [1])
    }

    @Test func callingZoomInIncreasesZoomFromTheCurrentValueThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 1.0)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.zoomIn()

        #expect(fake.appliedZooms.map(\.zoom).last!.isApproximatelyEqual(to: 1.1))
    }

    @Test func callingZoomOutDecreasesZoomFromTheCurrentValueThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 1.0)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.zoomOut()

        #expect(fake.appliedZooms.map(\.zoom).last!.isApproximatelyEqual(to: 0.9))
    }

    @Test func zoomingInRepeatedlyClampsAtTheUpperBound() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 4.95)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.zoomIn()
        orchestrator.zoomIn()

        #expect(fake.appliedZooms.map(\.zoom).last! <= 5.0)
    }

    @Test func callingResetZoomSetsZoomBackToOneHundredPercentThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 2.5)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.resetZoom()

        #expect(fake.appliedZooms.map(\.zoom).last!.isApproximatelyEqual(to: 1.0))
    }

    @Test func callingOpenSettingsPanelInvokesTheInjectedCallback() {
        let fake = FakePlatformOps()
        var openSettingsCallCount = 0
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, openSettings: {
            openSettingsCallCount += 1
        })
        orchestrator.start()

        orchestrator.openSettingsPanel()

        #expect(openSettingsCallCount == 1)
    }

    /// #62: the About panel's one entry point, shared by the App menu and (later) the tray. The
    /// panel is put up *before* the app is activated — the same order as the settings panel — so
    /// activation lands on the panel as the key window rather than on the widget.
    @Test func openingTheAboutPanelShowsItAndThenActivatesTheApp() {
        let fake = FakePlatformOps()
        var activationsSeenByTheClosure: [Int] = []
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, openAbout: {
            activationsSeenByTheClosure.append(fake.activateAppCallCount)
        })
        orchestrator.start()

        orchestrator.openAboutPanel()

        #expect(activationsSeenByTheClosure == [0])
        #expect(fake.activateAppCallCount == 1)
    }

    /// #62 / user story 53: from Ghost Mode, About must neither front the widget (it may never be
    /// key, ADR-0012) nor knock the widget out of Ghost Mode.
    @Test func openingTheAboutPanelInGhostModeLeavesTheWidgetAlone() {
        let fake = FakePlatformOps()
        var aboutCallCount = 0
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, openAbout: { aboutCallCount += 1 })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        let shownBefore = fake.shownWindowIDs
        let chromeChangesBefore = fake.nativeChromeVisibilityChanges.count

        orchestrator.openAboutPanel()

        #expect(aboutCallCount == 1)
        #expect(fake.shownWindowIDs == shownBefore)
        #expect(fake.nativeChromeVisibilityChanges.count == chromeChangesBefore)
    }

    @Test func pressingHiddenInGhostModeTogglesTheWidgetInAndOutOfInvisibility() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 0.2])
    }

    @Test func pressingHiddenInNormalModeDoesNothingAtAll() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        #expect(fake.contentOpacityChanges.isEmpty)
    }

    // #38: navigation failures route through the core so the error page shows through
    // `PlatformOps` rather than the platform layer deciding on its own to display it.

    @Test func navigationFailureShowsAnErrorPageWithTheGivenMessageThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateNavigationFailed("无法连接到服务器")

        #expect(fake.errorPagesShown.map(\.message) == ["无法连接到服务器"])
        #expect(fake.errorPagesShown.map(\.windowID) == [1])
    }

    @Test func aSuccessfulNavigationAfterAFailureDoesNotShowTheErrorPageAgain() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateNavigationFailed("无法连接到服务器")

        fake.simulateNavigationFinished()

        #expect(fake.errorPagesShown.count == 1)
    }

    @Test func skipsAUserHotkeyMappingThatCollidesWithAnActionHotkeyInsteadOfDoubleRegisteringIt() {
        // Regression test: Carbon allows registering the same combo twice in-process, which would
        // make both the mapped page-keystroke forward and the default action fire on one press.
        let fake = FakePlatformOps()
        let colliding = HotkeyMapping(trigger: DefaultHotkeys.hideWidget, pageKeystroke: Hotkey(keyCode: 1, modifierFlags: 0))
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [colliding])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        #expect(fake.registeredHotkeys.filter { $0 == DefaultHotkeys.hideWidget }.count == 1)
        #expect(fake.presentedAlerts.count == 1)
    }

    // #11/#46: forwarding mappings are registered by the orchestrator at launch and dispatched
    // against the *current* config on every press (see `handleGlobalHotkeyPressed`).

    @Test func registersEachForwardingMappingsTriggerAfterTheActionHotkeysOnStart() {
        let fake = FakePlatformOps()
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 0x31, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.registeredHotkeys == [DefaultHotkeys.toggleGhostMode, DefaultHotkeys.hideWidget, mapping.trigger])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func pressingAMappingsTriggerInGhostModeForwardsItsPageKeystroke() {
        let fake = FakePlatformOps()
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 0x31, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 0x7C, modifierFlags: 0))
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        fake.simulateHotkeyPressed(mapping.trigger)

        #expect(fake.forwardedKeystrokes == [mapping.pageKeystroke])
    }

    @Test func pressingAMappingsTriggerInNormalModeForwardsNothing() {
        let fake = FakePlatformOps()
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 0x31, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 0x7C, modifierFlags: 0))
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateHotkeyPressed(mapping.trigger)

        #expect(fake.forwardedKeystrokes.isEmpty)
    }

    @Test func aMappingsPageKeystrokeIsResolvedAtPressTimeSoEditingItNeedsNoReRegistration() {
        let fake = FakePlatformOps()
        let trigger = Hotkey(keyCode: 0x31, modifierFlags: 0)
        var config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            hotkeyMappings: [HotkeyMapping(trigger: trigger, pageKeystroke: Hotkey(keyCode: 0x7C, modifierFlags: 0))])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        config.hotkeyMappings = [HotkeyMapping(trigger: trigger, pageKeystroke: Hotkey(keyCode: 0x7B, modifierFlags: 0))]

        fake.simulateHotkeyPressed(trigger)

        #expect(fake.forwardedKeystrokes == [Hotkey(keyCode: 0x7B, modifierFlags: 0)])
    }

    @Test func presentsOneAlertWhenAMappingTriggerIsHeldByAnotherApp() {
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let mapping = HotkeyMapping(trigger: Hotkey(keyCode: 0x31, modifierFlags: 0), pageKeystroke: Hotkey(keyCode: 0x31, modifierFlags: 0))
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [mapping])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        // One alert for the action hotkeys, one for the mappings — never one per combo.
        #expect(fake.presentedAlerts.count == 2)
    }

    // #45: the action hotkeys register at their *configured* combos, and a press is resolved
    // against the current config.

    @Test func registersAnOverriddenActionHotkeyAtItsOverrideInsteadOfTheDefault() {
        let fake = FakePlatformOps()
        let custom = Hotkey(keyCode: 0x11, modifierFlags: 0x0100 | 0x0800)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyOverrides: [.toggleGhostMode: custom])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.registeredHotkeys == [custom, DefaultHotkeys.hideWidget])
    }

    @Test func pressingAnOverriddenActionHotkeyPerformsThatAction() {
        let fake = FakePlatformOps()
        let custom = Hotkey(keyCode: 0x11, modifierFlags: 0x0100 | 0x0800)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3, hotkeyOverrides: [.toggleGhostMode: custom])
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateHotkeyPressed(custom)

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
    }

    @Test func handleGlobalHotkeyPressedIgnoresAComboBoundToNothing() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.handleGlobalHotkeyPressed(Hotkey(keyCode: 0x7F, modifierFlags: 0))

        #expect(fake.contentOpacityChanges.isEmpty)
        #expect(fake.forwardedKeystrokes.isEmpty)
    }

    // #42: close is close, reopen is a fresh launch, and only the widget-bound parts repeat.

    @Test func reopeningAfterACloseRepeatsOnlyThePerWindowWorkNeverTheAppGlobalSetup() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        let hotkeyRegistrationsAfterStart = fake.registeredHotkeys.count

        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(fake.createTrayIconCallCount == 1)
        #expect(fake.registeredHotkeys.count == hotkeyRegistrationsAfterStart)
        #expect(fake.createdFrames.count == 2)
        #expect(fake.loadedURLs.map(\.windowID) == [1, 2])
        #expect(fake.shownWindowIDs == [1, 2])
        #expect(fake.toolbarVisibilityChanges.map(\.windowID) == [1, 2])
        #expect(fake.snapEnabledChanges.map(\.windowID) == [1, 2])
    }

    @Test func reopeningRegistersThePerWindowCallbacksOnTheNewWindow() {
        let fake = FakePlatformOps()
        var persistedURL: URL?
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, persistURL: { persistedURL = $0 })
        orchestrator.start()
        orchestrator.closeWidget()
        orchestrator.openWidget()

        let navigatedURL = URL(string: "https://example.org")!
        fake.simulateURLSubmitted(navigatedURL, windowID: 2)
        fake.simulateNavigationFinished(windowID: 2)
        fake.simulateNavigationFailed("离线", windowID: 2)
        fake.simulateGhostModeToggleRequested(windowID: 2)

        #expect(persistedURL == navigatedURL)
        #expect(fake.loadedURLs.last?.windowID == 2)
        #expect(!fake.injectedScripts.filter { $0.windowID == 2 }.isEmpty)
        #expect(fake.errorPagesShown.map(\.windowID) == [2])
        #expect(fake.mousePassthroughChanges.map(\.windowID) == [2])
    }

    @Test func closingTheWidgetClosesTheWindowThroughPlatformOpsAndPersistsItsGeometry() {
        let fake = FakePlatformOps()
        fake.stubbedCapturedWindowState = WindowState(frame: WindowFrame(x: 10, y: 20, width: 900, height: 700), zoom: 1.25)
        var persisted: WindowState?
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, persistWindowState: { persisted = $0 })
        orchestrator.start()

        orchestrator.closeWidget()

        #expect(fake.closedWindowIDs == [1])
        #expect(persisted == fake.stubbedCapturedWindowState)
        #expect(!orchestrator.hasActiveWidget)
    }

    @Test func theRedCloseButtonAndCloseWidgetShareOneTeardownPath() {
        // The platform's will-close callback is the single teardown point — a close that never
        // went through `closeWidget()` (the red button) must leave the core in the same state.
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.simulateWindowWillClose()

        #expect(!orchestrator.hasActiveWidget)
        #expect(fake.closedWindowIDs.isEmpty)
    }

    @Test func closingTwiceDoesNotCloseTwice() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.closeWidget()
        orchestrator.closeWidget()

        #expect(fake.closedWindowIDs == [1])
    }

    @Test func reopeningReResolvesStartupContentFromTheCurrentConfig() {
        // A fixed startup URL wins over the page being viewed at close — reopen is a fresh launch.
        let fake = FakePlatformOps()
        let fixedStartupURL = URL(string: "https://fixed-startup.example.com")!
        var config = WidgetConfig(url: URL(string: "https://last-visited.example.com")!, startupTarget: .url(fixedStartupURL))
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, persistURL: { config.url = $0 })
        orchestrator.start()
        fake.simulateURLSubmitted(URL(string: "https://browsed-to.example.com")!)

        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(fake.loadedURLs.last?.url == fixedStartupURL)
        #expect(fake.loadedURLs.last?.windowID == 2)
    }

    @Test func reopeningWithoutAStartupTargetResumesTheURLPersistedMidSession() {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, persistURL: { config.url = $0 })
        orchestrator.start()
        let browsedTo = URL(string: "https://browsed-to.example.com")!
        fake.simulateURLSubmitted(browsedTo)

        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(fake.loadedURLs.map(\.url) == [URL(string: "https://example.com")!, browsedTo, browsedTo])
    }

    @Test func reopeningReResolvesToTheEmptyPageWhenThatIsTheConfiguredStartup() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, startupTarget: .emptyPage)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(fake.emptyPageShownWindowIDs == [1, 2])
        #expect(fake.loadedURLs.isEmpty)
    }

    @Test func reopeningUsesTheGeometryAndZoomPersistedAtClose() {
        let fake = FakePlatformOps()
        let closedAt = WindowState(frame: WindowFrame(x: 300, y: 200, width: 640, height: 480), zoom: 1.5)
        fake.stubbedCapturedWindowState = closedAt
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(
            platformOps: fake, currentConfig: { config }, persistWindowState: { config.windowState = $0 })
        orchestrator.start()

        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(fake.createdFrames.last == closedAt.frame)
        #expect(fake.appliedZooms.map(\.zoom) == [1.5])
        #expect(fake.appliedZooms.map(\.windowID) == [2])
    }

    @Test func reopeningAlwaysStartsInNormalModeEvenIfClosedWhileInGhostMode() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateWindowWillClose()
        orchestrator.openWidget()

        // A toggle from the fresh state must *enter* Ghost Mode on the new window — proving the
        // new controller started in Normal Mode rather than inheriting the old one's state.
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, true])
        #expect(fake.mousePassthroughChanges.map(\.windowID) == [1, 2])
    }

    @Test func bothActionHotkeysAreSilentNoOpsWhileTheWidgetIsClosed() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        orchestrator.closeWidget()
        let opacityCount = fake.contentOpacityChanges.count
        let passthroughCount = fake.mousePassthroughChanges.count

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        #expect(fake.contentOpacityChanges.count == opacityCount)
        #expect(fake.mousePassthroughChanges.count == passthroughCount)
        #expect(fake.pinnedChanges.isEmpty)
        #expect(fake.nativeChromeVisibilityChanges.isEmpty)
        #expect(fake.shownWindowIDs == [1])
        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func widgetBoundOperationsDoNothingWhileTheWidgetIsClosed() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        orchestrator.closeWidget()

        orchestrator.reloadPage()
        orchestrator.zoomIn()
        orchestrator.resetZoom()
        orchestrator.persistCurrentWindowState()
        orchestrator.reapplyConfiguration()

        #expect(fake.reloadedWindowIDs.isEmpty)
        #expect(fake.appliedZooms.isEmpty)
        #expect(fake.snapEnabledChanges.count == 1)
    }

    @Test func aDockReopenRequestReopensTheClosedWidget() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        orchestrator.closeWidget()

        fake.simulateReopenRequested()

        #expect(fake.createdFrames.count == 2)
        #expect(orchestrator.hasActiveWidget)
    }

    @Test func trayOpenWidgetEntryReopensTheClosedWidget() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        orchestrator.closeWidget()

        fake.trayItem("打开窗口").action()

        #expect(fake.createdFrames.count == 2)
        #expect(orchestrator.hasActiveWidget)
    }

    @Test func openWidgetWhileAlreadyOpenJustFrontsTheExistingWindow() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayItem("打开窗口").action()

        #expect(fake.createdFrames.count == 1)
        #expect(fake.shownWindowIDs == [1, 1])
    }

    @Test func openWidgetWhileInGhostModeLeavesGhostModeInsteadOfFrontingAClickThroughWindow() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        orchestrator.openWidget()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
        #expect(fake.shownWindowIDs == [1, 1])
    }

    // #46: settings are read at the point of use; `reapplyConfiguration` pushes the few that
    // need pushing.

    @Test func injectsTheScriptsConfiguredAtNavigationTimeNotAtLaunch() {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        config.customScript = "console.log('added later')"
        config.disabledBuiltInScriptIDs = [BuiltInScripts.all[0].id]

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.map(\.source).last == "console.log('added later')")
        #expect(!fake.injectedScripts.map(\.source).contains(BuiltInScripts.all[0].source))
    }

    @Test func entersGhostModeAtTheOpacityConfiguredNowNotAtLaunch() {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        config.ghostOpacity = 0.6

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.6])
    }

    @Test(arguments: [true, false])
    func reapplyConfigurationPushesTheCurrentSnapPreferenceToTheWindow(_ enabled: Bool) {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!, isSnapEnabled: !enabled)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        config.isSnapEnabled = enabled

        orchestrator.reapplyConfiguration()

        #expect(fake.snapEnabledChanges.map(\.enabled) == [!enabled, enabled])
    }

    @Test func reapplyConfigurationPushesANewOpacityDownWhileInGhostMode() {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        config.ghostOpacity = 0.7

        orchestrator.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.7])
    }

    @Test func reapplyConfigurationNeverTouchesOpacityInNormalMode() {
        let fake = FakePlatformOps()
        var config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        config.ghostOpacity = 0.7

        orchestrator.reapplyConfiguration()

        #expect(fake.contentOpacityChanges.isEmpty)
    }

    // #57: the main menu's widget commands, gated in one place

    @Test(arguments: [
        (state: WidgetStateUnderTest.noWidget, command: WidgetCommand.reload, canPerform: false),
        (state: .noWidget, command: .zoomIn, canPerform: false),
        (state: .noWidget, command: .zoomOut, canPerform: false),
        (state: .noWidget, command: .resetZoom, canPerform: false),
        (state: .normalMode, command: .reload, canPerform: true),
        (state: .normalMode, command: .zoomIn, canPerform: true),
        (state: .normalMode, command: .zoomOut, canPerform: true),
        (state: .normalMode, command: .resetZoom, canPerform: true),
        (state: .ghostMode, command: .reload, canPerform: false),
        (state: .ghostMode, command: .zoomIn, canPerform: false),
        (state: .ghostMode, command: .zoomOut, canPerform: false),
        (state: .ghostMode, command: .resetZoom, canPerform: false),
        (state: .noWidget, command: .openLocation, canPerform: true),
        (state: .normalMode, command: .openLocation, canPerform: true),
        (state: .ghostMode, command: .openLocation, canPerform: false),
    ])
    func widgetCommandsCanOnlyBePerformedOnAWidgetInNormalMode(
        _ row: (state: WidgetStateUnderTest, command: WidgetCommand, canPerform: Bool)
    ) {
        let (_, orchestrator) = makeOrchestrator(in: row.state)

        #expect(orchestrator.canPerform(row.command) == row.canPerform)
    }

    /// The perform side refuses exactly what the can-perform side reports — a key equivalent that
    /// slips past menu validation still can't reload or zoom a Ghost Mode window.
    @Test(arguments: [
        (state: WidgetStateUnderTest.noWidget, command: WidgetCommand.reload, performs: false),
        (state: .noWidget, command: .zoomIn, performs: false),
        (state: .noWidget, command: .zoomOut, performs: false),
        (state: .noWidget, command: .resetZoom, performs: false),
        (state: .normalMode, command: .reload, performs: true),
        (state: .normalMode, command: .zoomIn, performs: true),
        (state: .normalMode, command: .zoomOut, performs: true),
        (state: .normalMode, command: .resetZoom, performs: true),
        (state: .ghostMode, command: .reload, performs: false),
        (state: .ghostMode, command: .zoomIn, performs: false),
        (state: .ghostMode, command: .zoomOut, performs: false),
        (state: .ghostMode, command: .resetZoom, performs: false),
        (state: .noWidget, command: .openLocation, performs: true),
        (state: .normalMode, command: .openLocation, performs: true),
        (state: .ghostMode, command: .openLocation, performs: false),
    ])
    func performingAWidgetCommandReachesPlatformOpsOnlyWhenItCanBePerformed(
        _ row: (state: WidgetStateUnderTest, command: WidgetCommand, performs: Bool)
    ) {
        let (fake, orchestrator) = makeOrchestrator(in: row.state)
        let before = fake.effectCount(of: row.command)

        orchestrator.perform(row.command)

        #expect(fake.effectCount(of: row.command) == before + (row.performs ? 1 : 0))
    }

    @Test(arguments: [
        (command: WidgetCommand.zoomIn, zoom: 1.6),
        (command: .zoomOut, zoom: 1.4),
        (command: .resetZoom, zoom: 1.0),
    ])
    func performingAZoomCommandStepsFromTheCurrentZoom(_ row: (command: WidgetCommand, zoom: Double)) {
        let fake = FakePlatformOps()
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 1.5)
        )
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        orchestrator.perform(row.command)

        #expect(fake.appliedZooms.map(\.zoom).last!.isApproximatelyEqual(to: row.zoom))
    }

    @Test func leavingGhostModeMakesTheWidgetCommandsPerformableAgain() {
        let (fake, orchestrator) = makeOrchestrator(in: .ghostMode)
        fake.stubbedNavigationState = NavigationState(canGoBack: true, canGoForward: true, isLoading: true)

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(WidgetCommand.allCases.allSatisfy { orchestrator.canPerform($0) })
    }

    // #59: 历史记录 → 返回 / 前进, offered exactly when the toolbar's segments are

    @Test(arguments: [
        (state: WidgetStateUnderTest.normalMode, canGoBack: true, canGoForward: false, command: WidgetCommand.goBack, canPerform: true),
        (state: .normalMode, canGoBack: false, canGoForward: true, command: .goBack, canPerform: false),
        (state: .normalMode, canGoBack: false, canGoForward: true, command: .goForward, canPerform: true),
        (state: .normalMode, canGoBack: true, canGoForward: false, command: .goForward, canPerform: false),
        (state: .noWidget, canGoBack: true, canGoForward: true, command: .goBack, canPerform: false),
        (state: .noWidget, canGoBack: true, canGoForward: true, command: .goForward, canPerform: false),
        (state: .ghostMode, canGoBack: true, canGoForward: true, command: .goBack, canPerform: false),
        (state: .ghostMode, canGoBack: true, canGoForward: true, command: .goForward, canPerform: false),
    ])
    func historyCommandsFollowTheNavigationStateOnAWidgetInNormalMode(
        _ row: (state: WidgetStateUnderTest, canGoBack: Bool, canGoForward: Bool, command: WidgetCommand, canPerform: Bool)
    ) {
        let (fake, orchestrator) = makeOrchestrator(in: row.state)
        fake.stubbedNavigationState = NavigationState(canGoBack: row.canGoBack, canGoForward: row.canGoForward)

        #expect(orchestrator.canPerform(row.command) == row.canPerform)
    }

    @Test(arguments: [
        (state: WidgetStateUnderTest.normalMode, command: WidgetCommand.goBack, back: 1, forward: 0),
        (state: .normalMode, command: .goForward, back: 0, forward: 1),
        (state: .noWidget, command: .goBack, back: 0, forward: 0),
        (state: .noWidget, command: .goForward, back: 0, forward: 0),
        (state: .ghostMode, command: .goBack, back: 0, forward: 0),
        (state: .ghostMode, command: .goForward, back: 0, forward: 0),
    ])
    func performingAHistoryCommandForwardsTheMatchingPlatformOpsCall(
        _ row: (state: WidgetStateUnderTest, command: WidgetCommand, back: Int, forward: Int)
    ) {
        let (fake, orchestrator) = makeOrchestrator(in: row.state)
        fake.stubbedNavigationState = NavigationState(canGoBack: true, canGoForward: true)

        orchestrator.perform(row.command)

        #expect(fake.wentBackWindowIDs.count == row.back)
        #expect(fake.wentForwardWindowIDs.count == row.forward)
    }

    @Test(arguments: [WidgetCommand.goBack, .goForward])
    func performingAHistoryCommandTheNavigationStateRulesOutDoesNothing(_ command: WidgetCommand) {
        let (fake, orchestrator) = makeOrchestrator(in: .normalMode)
        fake.stubbedNavigationState = NavigationState(canGoBack: false, canGoForward: false)

        orchestrator.perform(command)

        #expect(fake.wentBackWindowIDs.isEmpty)
        #expect(fake.wentForwardWindowIDs.isEmpty)
    }

    // #61: 打开位置… (⌘L)

    @Test func openLocationFocusesTheAddressBarOfTheOpenWidget() {
        let (fake, orchestrator) = makeOrchestrator(in: .normalMode)

        orchestrator.perform(.openLocation)

        #expect(fake.addressBarFocuses.map(\.windowID) == [1])
        #expect(fake.createdFrames.count == 1)
    }

    @Test func openLocationWorksOnTheEmptyPage() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: nil)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        #expect(fake.emptyPageShownWindowIDs == [1])

        #expect(orchestrator.canPerform(.openLocation))
        orchestrator.perform(.openLocation)

        #expect(fake.addressBarFocuses.map(\.windowID) == [1])
    }

    /// Without a widget, ⌘L is a reopen (the same fresh launch as the tray/Dock) followed by the
    /// focus — and the focus lands on the *new* window, only once that window is on screen.
    @Test func openLocationWithoutAWidgetReopensItThenFocusesTheNewAddressBar() {
        let (fake, orchestrator) = makeOrchestrator(in: .noWidget)

        orchestrator.perform(.openLocation)

        #expect(fake.createdFrames.count == 2)
        #expect(fake.addressBarFocuses.map(\.windowID) == [2])
        #expect(fake.addressBarFocuses.map(\.windowWasShown) == [true])
        #expect(orchestrator.hasActiveWidget)
    }

    /// The focus doesn't wait for the startup page: it happens during the same call, before any
    /// navigation has finished.
    @Test func openLocationAfterAReopenDoesNotWaitForThePageToLoad() {
        let (fake, orchestrator) = makeOrchestrator(in: .noWidget)

        orchestrator.perform(.openLocation)

        #expect(fake.addressBarFocuses.map(\.loadedURLCount) == [2])
        #expect(fake.injectedScripts.isEmpty)
    }

    @Test func openLocationInGhostModeNeitherFocusesNorLeavesGhostMode() {
        let (fake, orchestrator) = makeOrchestrator(in: .ghostMode)
        let passthroughChanges = fake.mousePassthroughChanges.count

        orchestrator.perform(.openLocation)

        #expect(fake.addressBarFocuses.isEmpty)
        #expect(fake.mousePassthroughChanges.count == passthroughChanges)
    }

    // #60: 停止 is offered only while the page is loading, on top of #57's rules

    @Test(arguments: [
        (state: WidgetStateUnderTest.noWidget, isLoading: true, canPerform: false),
        (state: .noWidget, isLoading: false, canPerform: false),
        (state: .normalMode, isLoading: true, canPerform: true),
        (state: .normalMode, isLoading: false, canPerform: false),
        (state: .ghostMode, isLoading: true, canPerform: false),
        (state: .ghostMode, isLoading: false, canPerform: false),
    ])
    func stopCanOnlyBePerformedWhileTheWidgetsPageIsLoading(
        _ row: (state: WidgetStateUnderTest, isLoading: Bool, canPerform: Bool)
    ) {
        let (fake, orchestrator) = makeOrchestrator(in: row.state)
        fake.stubbedNavigationState.isLoading = row.isLoading

        #expect(orchestrator.canPerform(.stop) == row.canPerform)
    }

    @Test(arguments: [
        (state: WidgetStateUnderTest.noWidget, isLoading: true, performs: false),
        (state: .normalMode, isLoading: true, performs: true),
        (state: .normalMode, isLoading: false, performs: false),
        (state: .ghostMode, isLoading: true, performs: false),
    ])
    func performingStopForwardsToPlatformOpsOnlyWhenItCanBePerformed(
        _ row: (state: WidgetStateUnderTest, isLoading: Bool, performs: Bool)
    ) {
        let (fake, orchestrator) = makeOrchestrator(in: row.state)
        fake.stubbedNavigationState.isLoading = row.isLoading

        orchestrator.perform(.stop)

        #expect(fake.stoppedLoadingWindowIDs == (row.performs ? [1] : []))
    }

    /// 重新载入页面 stays offered mid-load — only 停止 depends on the loading state.
    @Test func reloadStaysPerformableWhileThePageIsLoading() {
        let (fake, orchestrator) = makeOrchestrator(in: .normalMode)
        fake.stubbedNavigationState.isLoading = true

        #expect(orchestrator.canPerform(.reload))
    }

    private func makeOrchestrator(in state: WidgetStateUnderTest) -> (FakePlatformOps, Orchestrator) {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        switch state {
        case .noWidget: orchestrator.closeWidget()
        case .normalMode: break
        case .ghostMode: fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        }
        return (fake, orchestrator)
    }
}

enum WidgetStateUnderTest: Sendable {
    case noWidget, normalMode, ghostMode
}

private extension FakePlatformOps {
    /// How many times `command`'s platform-side effect has happened so far.
    func effectCount(of command: WidgetCommand) -> Int {
        switch command {
        case .reload: reloadedWindowIDs.count
        case .stop: stoppedLoadingWindowIDs.count
        case .zoomIn, .zoomOut, .resetZoom: appliedZooms.count
        case .goBack: wentBackWindowIDs.count
        case .goForward: wentForwardWindowIDs.count
        case .openLocation: addressBarFocuses.count
        }
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
