import Foundation
import Testing

@testable import MochiCore

@Suite struct OrchestratorTests {
    @Test func startsWidgetWindowUsingPersistedFrameAndLoadsConfiguredURL() {
        let fake = FakePlatformOps()
        fake.stubbedScreens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let orchestrator = Orchestrator(platformOps: fake)
        let persistedFrame = WindowFrame(x: 50, y: 50, width: 800, height: 600)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: persistedFrame, zoom: 1.5)
        )

        orchestrator.start(config: config)

        #expect(fake.createdFrames == [persistedFrame])
        #expect(fake.loadedURLs.map(\.url) == [config.url])
        #expect(fake.appliedZooms.map(\.zoom) == [1.5])
        #expect(fake.shownWindowIDs == [1])
    }

    @Test func fallsBackToSafeDefaultFrameWhenPersistedFrameIsOffscreen() {
        let fake = FakePlatformOps()
        let primaryScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        fake.stubbedScreens = [primaryScreen]
        let orchestrator = Orchestrator(platformOps: fake)
        let offscreenFrame = WindowFrame(x: 10_000, y: 10_000, width: 800, height: 600)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: offscreenFrame, zoom: 1.0)
        )

        orchestrator.start(config: config)

        #expect(fake.createdFrames == [WindowPlacement.safeDefault(in: primaryScreen)])
    }

    @Test func doesNotApplyZoomWhenNoWindowStateIsPersisted() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.appliedZooms.isEmpty)
    }

    @Test func persistsCapturedWindowStateWhenWindowWillClose() {
        let fake = FakePlatformOps()
        fake.stubbedCapturedWindowState = WindowState(
            frame: WindowFrame(x: 10, y: 20, width: 900, height: 700), zoom: 1.25)
        var persisted: WindowState?
        let orchestrator = Orchestrator(platformOps: fake) { state in
            persisted = state
        }
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)
        fake.simulateWindowWillClose()

        #expect(persisted == fake.stubbedCapturedWindowState)
    }

    @Test func persistCurrentWindowStateCanBeTriggeredExplicitlyOnAppTermination() {
        let fake = FakePlatformOps()
        fake.stubbedCapturedWindowState = WindowState(
            frame: WindowFrame(x: 5, y: 6, width: 700, height: 500), zoom: 0.8)
        var persisted: WindowState?
        let orchestrator = Orchestrator(platformOps: fake) { state in
            persisted = state
        }
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)
        orchestrator.persistCurrentWindowState()

        #expect(persisted == fake.stubbedCapturedWindowState)
    }

    @Test func showsToolbarOnStartThroughPlatformOpsRatherThanDirectWindowAccess() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.toolbarVisibilityChanges.map(\.visible) == [true])
        #expect(fake.toolbarVisibilityChanges.map(\.windowID) == [1])
    }

    @Test func submittingURLFromAddressBarLoadsItAndPersistsItOverConfiguredURL() {
        let fake = FakePlatformOps()
        var persistedURL: URL?
        let orchestrator = Orchestrator(platformOps: fake, persistURL: { url in
            persistedURL = url
        })
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        let navigatedURL = URL(string: "https://example.org")!
        fake.simulateURLSubmitted(navigatedURL)

        #expect(fake.loadedURLs.map(\.url) == [config.url, navigatedURL])
        #expect(persistedURL == navigatedURL)
    }

    @Test func appliesPersistedPinnedStateOnStartThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, isPinned: true)

        orchestrator.start(config: config)

        #expect(fake.pinnedChanges.map(\.pinned) == [true])
        #expect(fake.pinnedChanges.map(\.windowID) == [1])
    }

    @Test func togglingPinFromTheWindowPersistsTheNewState() {
        let fake = FakePlatformOps()
        var persistedPinned: Bool?
        let orchestrator = Orchestrator(platformOps: fake, persistPinned: { pinned in
            persistedPinned = pinned
        })
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulatePinnedChanged(true)

        #expect(persistedPinned == true)
    }

    @Test func injectsBuiltInScriptsThroughPlatformOpsWhenNavigationFinishes() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.map(\.source) == BuiltInScripts.all.map(\.source))
    }

    @Test func injectsConfiguredCustomScriptThroughPlatformOpsWhenNavigationFinishes() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, customScript: "console.log('hi')")
        orchestrator.start(config: config)

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.map(\.source).last == "console.log('hi')")
    }

    @Test func doesNotInjectACustomScriptWhenNoneIsConfigured() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateNavigationFinished()

        #expect(fake.injectedScripts.count == BuiltInScripts.all.count)
    }

    @Test func skipsInjectingABuiltInScriptDisabledInSettings() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let disabledID = BuiltInScripts.all[0].id
        let config = WidgetConfig(url: URL(string: "https://example.com")!, disabledBuiltInScriptIDs: [disabledID])
        orchestrator.start(config: config)

        fake.simulateNavigationFinished()

        #expect(!fake.injectedScripts.map(\.source).contains(BuiltInScripts.all[0].source))
        #expect(fake.injectedScripts.count == BuiltInScripts.all.count - 1)
    }

    @Test func openingSettingsFromTheToolbarInvokesTheInjectedCallback() {
        let fake = FakePlatformOps()
        var openSettingsCallCount = 0
        let orchestrator = Orchestrator(platformOps: fake, openSettings: {
            openSettingsCallCount += 1
        })
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateSettingsRequested()

        #expect(openSettingsCallCount == 1)
    }

    @Test func registersAllDefaultHotkeysOnStartInAFixedOrder() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(
            fake.registeredHotkeys == [
                DefaultHotkeys.toggleGhostMode,
                DefaultHotkeys.summonToolbar,
                DefaultHotkeys.reloadPage,
                DefaultHotkeys.zoomIn,
                DefaultHotkeys.zoomOut,
                DefaultHotkeys.quickHideWidget,
                DefaultHotkeys.resizeWindow,
                DefaultHotkeys.togglePin,
            ])
    }

    @Test func presentsAnAlertWhenHotkeyRegistrationFailsInsteadOfFailingSilently() {
        let fake = FakePlatformOps()
        fake.stubbedHotkeyRegistrationSucceeds = false
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.presentedAlerts.count == 1)
    }

    @Test func doesNotPresentAnAlertWhenHotkeyRegistrationSucceeds() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.presentedAlerts.isEmpty)
    }

    @Test func pressingTheGlobalHotkeyTogglesGhostModeThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
    }

    @Test func appliesConfiguredSnapThresholdOnStartThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, snapThreshold: 32)

        orchestrator.start(config: config)

        #expect(fake.snapThresholdChanges.map(\.threshold) == [32])
    }

    @Test func createsTheTrayIconWithFourEntriesInOrderOnStart() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.trayMenuItems.map(\.title) == ["退出 Ghost Mode", "切换 Ghost Mode", "打开设置", "退出应用"])
    }

    @Test func trayExitGhostModeEntryDoesNothingWhenAlreadyInNormalMode() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.trayMenuItems[0].action()

        #expect(fake.mousePassthroughChanges.isEmpty)
        #expect(fake.contentOpacityChanges.isEmpty)
    }

    @Test func trayExitGhostModeEntryRestoresNormalModeEvenWhileFullyHiddenAndClickThrough() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        orchestrator.start(config: config)
        fake.simulateHotkeyPressed()
        fake.simulateMouseEntered()

        fake.trayMenuItems[0].action()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
        #expect(fake.windowHiddenChanges.map(\.hidden) == [true, false])
    }

    @Test func trayToggleGhostModeEntryTogglesModeThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        orchestrator.start(config: config)

        fake.trayMenuItems[1].action()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
    }

    @Test func trayOpenSettingsEntryInvokesTheInjectedCallback() {
        let fake = FakePlatformOps()
        var openSettingsCallCount = 0
        let orchestrator = Orchestrator(platformOps: fake, openSettings: {
            openSettingsCallCount += 1
        })
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.trayMenuItems[2].action()

        #expect(openSettingsCallCount == 1)
    }

    @Test func trayQuitEntryTerminatesTheAppThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.trayMenuItems[3].action()

        #expect(fake.terminateAppCallCount == 1)
    }

    // MARK: - #10: Ghost Mode toolbar summon

    @Test func pressingTheSummonToolbarHotkeyDoesNothingInNormalMode() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.summonToolbar)

        #expect(fake.summonedToolbarVisibilityChanges.isEmpty)
    }

    @Test func pressingTheSummonToolbarHotkeyInGhostModeShowsTheOverlayAndDisablesPassthrough() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        fake.simulateHotkeyPressed(DefaultHotkeys.summonToolbar)

        #expect(fake.summonedToolbarVisibilityChanges.map(\.visible) == [true])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
    }

    @Test func clickingTheSummonedToolbarsGhostModeToggleButtonTogglesGhostModeThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        orchestrator.start(config: config)

        fake.simulateSummonedToolbarGhostModeToggleRequested()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
    }

    // MARK: - #12: default utility hotkeys

    @Test func pressingTheReloadHotkeyReloadsThePageThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.reloadPage)

        #expect(fake.reloadedWindowIDs == [1])
    }

    @Test func pressingZoomInIncreasesZoomFromTheCurrentValueThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 1.0)
        )
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.zoomIn)

        #expect(fake.appliedZooms.map(\.zoom).last!.isApproximatelyEqual(to: 1.1))
    }

    @Test func pressingZoomOutDecreasesZoomFromTheCurrentValueThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 1.0)
        )
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.zoomOut)

        #expect(fake.appliedZooms.map(\.zoom).last!.isApproximatelyEqual(to: 0.9))
    }

    @Test func zoomingInRepeatedlyClampsAtTheUpperBound() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600), zoom: 4.95)
        )
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.zoomIn)
        fake.simulateHotkeyPressed(DefaultHotkeys.zoomIn)

        #expect(fake.appliedZooms.map(\.zoom).last! <= 5.0)
    }

    @Test func pressingQuickHideInNormalModeTogglesWindowHiddenThroughPlatformOps() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.quickHideWidget)
        fake.simulateHotkeyPressed(DefaultHotkeys.quickHideWidget)

        #expect(fake.windowHiddenChanges.map(\.hidden) == [true, false])
    }

    @Test func pressingQuickHideWhileInGhostModeDoesNothingSoItNeverFightsGhostModesOwnHiddenState() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        fake.simulateHotkeyPressed(DefaultHotkeys.quickHideWidget)

        #expect(fake.windowHiddenChanges.isEmpty)
    }

    @Test func togglingGhostModeWhileQuickHiddenRestoresWindowVisibilityBeforeGhostModeTakesOver() {
        // Regression test: entering Ghost Mode used to only clear the `isQuickHidden` bookkeeping
        // flag without ever telling the platform to un-hide the window, leaving the widget stuck
        // invisible even while `mode == .ghost` expected to start out visible.
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)
        fake.simulateHotkeyPressed(DefaultHotkeys.quickHideWidget)  // hide in Normal Mode

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(fake.windowHiddenChanges.map(\.hidden) == [true, false])
    }

    @Test func pressingResizeTogglesTheWindowBetweenCompactAndDefaultSizeThroughPlatformOps() {
        let fake = FakePlatformOps()
        fake.stubbedScreens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        fake.stubbedCapturedWindowState = WindowState(
            frame: WindowFrame(x: 100, y: 100, width: WindowPlacement.defaultWidth, height: WindowPlacement.defaultHeight),
            zoom: 1.0
        )
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.resizeWindow)

        #expect(fake.windowFrameChanges.map(\.frame.width) == [WindowPlacement.compactWidth])
        #expect(fake.windowFrameChanges.map(\.frame.height) == [WindowPlacement.compactHeight])
    }

    @Test func pressingResizeClampsAgainstTheScreenTheWindowIsActuallyOnRatherThanJustThePrimary() {
        let fake = FakePlatformOps()
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: 0, width: 800, height: 600)
        fake.stubbedScreens = [primary, secondary]
        fake.stubbedCapturedWindowState = WindowState(
            frame: WindowFrame(x: 1440 + 700, y: 0, width: WindowPlacement.compactWidth, height: WindowPlacement.compactHeight),
            zoom: 1.0
        )
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.resizeWindow)

        let resized = fake.windowFrameChanges.first!.frame
        #expect(resized.width == min(WindowPlacement.defaultWidth, Double(secondary.width)))
        #expect(resized.x + resized.width <= Double(secondary.maxX))
    }

    @Test func pressingTogglePinFlipsPinnedStateAndPersistsItThroughPlatformOps() {
        let fake = FakePlatformOps()
        var persistedPinned: Bool?
        let orchestrator = Orchestrator(platformOps: fake, persistPinned: { persistedPinned = $0 })
        let config = WidgetConfig(url: URL(string: "https://example.com")!, isPinned: false)
        orchestrator.start(config: config)

        fake.simulateHotkeyPressed(DefaultHotkeys.togglePin)

        #expect(fake.pinnedChanges.map(\.pinned).last == true)
        #expect(persistedPinned == true)
    }

    @Test func skipsAUserHotkeyMappingThatCollidesWithADefaultHotkeyInsteadOfDoubleRegisteringIt() {
        // Regression test: Carbon allows registering the same combo twice in-process, which would
        // make both the mapped page-keystroke forward and the default action fire on one press.
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let colliding = HotkeyMapping(trigger: DefaultHotkeys.reloadPage, pageKeystroke: Hotkey(keyCode: 1, modifierFlags: 0))
        let config = WidgetConfig(url: URL(string: "https://example.com")!, hotkeyMappings: [colliding])

        orchestrator.start(config: config)

        #expect(fake.registeredHotkeys.filter { $0 == DefaultHotkeys.reloadPage }.count == 1)
        #expect(fake.presentedAlerts.count == 1)
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
