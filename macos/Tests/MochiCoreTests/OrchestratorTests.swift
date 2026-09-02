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

    @Test func registersTheDefaultGhostModeHotkeyOnStart() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake)
        let config = WidgetConfig(url: URL(string: "https://example.com")!)

        orchestrator.start(config: config)

        #expect(fake.registeredHotkeys == [DefaultHotkeys.toggleGhostMode])
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
}
