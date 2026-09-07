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

    @Test func openingSettingsFromTheToolbarInvokesTheInjectedCallback() {
        let fake = FakePlatformOps()
        var openSettingsCallCount = 0
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, openSettings: {
            openSettingsCallCount += 1
        })
        orchestrator.start()

        fake.simulateSettingsRequested()

        #expect(openSettingsCallCount == 1)
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

    @Test func createsTheTrayIconWithFiveEntriesInOrderOnStart() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })

        orchestrator.start()

        #expect(fake.trayMenuItems.map(\.title) == ["打开 Widget", "退出 Ghost Mode", "切换 Ghost Mode", "打开设置", "退出应用"])
    }

    @Test func trayExitGhostModeEntryDoesNothingWhenAlreadyInNormalMode() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayMenuItems[1].action()

        #expect(fake.mousePassthroughChanges.isEmpty)
        #expect(fake.contentOpacityChanges.isEmpty)
    }

    @Test func trayExitGhostModeEntryRestoresNormalModeEvenWhileFullyHiddenAndClickThrough() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.2)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)

        fake.trayMenuItems[1].action()

        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.2, 0.0, 1.0])
        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true, false])
    }

    @Test func trayToggleGhostModeEntryTogglesModeThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!, ghostOpacity: 0.3)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayMenuItems[2].action()

        #expect(fake.mousePassthroughChanges.map(\.enabled) == [true])
        #expect(fake.contentOpacityChanges.map(\.opacity) == [0.3])
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
        let viaTray = captureEntrySignature { $0.trayMenuItems[2].action() }

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
        fake.trayMenuItems[2].action()

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

        fake.trayMenuItems[3].action()

        #expect(openSettingsCallCount == 1)
    }

    @Test func trayQuitEntryTerminatesTheAppThroughPlatformOps() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayMenuItems[4].action()

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

        fake.trayMenuItems[0].action()

        #expect(fake.createdFrames.count == 2)
        #expect(orchestrator.hasActiveWidget)
    }

    @Test func openWidgetWhileAlreadyOpenJustFrontsTheExistingWindow() {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        fake.trayMenuItems[0].action()

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
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
