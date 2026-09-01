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
}
