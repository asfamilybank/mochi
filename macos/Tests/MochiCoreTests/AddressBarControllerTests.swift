import Foundation
import Testing

@testable import MochiCore

@Suite struct AddressBarControllerTests {
    private func makeWindow(_ platformOps: FakePlatformOps) -> WidgetWindowHandle {
        platformOps.createWidgetWindow(initialFrame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func setsTheMochiFallbackImmediatelyWhenNothingHasLoaded() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)

        _ = AddressBarController(platformOps: platformOps, window: window)

        #expect(platformOps.windowTitleChanges.last?.title == "Mochi")
    }

    @Test func fallsBackToHostBeforeAPageTitleArrives() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)
        let controller = AddressBarController(platformOps: platformOps, window: window)

        controller.urlLoaded(URL(string: "https://example.com/page")!)

        #expect(platformOps.windowTitleChanges.last?.title == "example.com")
    }

    @Test func prefersThePageTitleOnceReported() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)
        let controller = AddressBarController(platformOps: platformOps, window: window)
        controller.urlLoaded(URL(string: "https://example.com")!)

        platformOps.simulatePageTitleChanged("Example Site")

        #expect(platformOps.windowTitleChanges.last?.title == "Example Site")
    }

    @Test func clearsThePreviousPagesTitleWhenNavigatingToANewURL() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)
        let controller = AddressBarController(platformOps: platformOps, window: window)
        controller.urlLoaded(URL(string: "https://example.com")!)
        platformOps.simulatePageTitleChanged("Example Site")

        controller.urlLoaded(URL(string: "https://other.com")!)

        #expect(platformOps.windowTitleChanges.last?.title == "other.com")
    }

    @Test func fallsBackToHostAgainWhenTheTitleClears() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)
        let controller = AddressBarController(platformOps: platformOps, window: window)
        controller.urlLoaded(URL(string: "https://example.com")!)
        platformOps.simulatePageTitleChanged("Example Site")

        platformOps.simulatePageTitleChanged(nil)

        #expect(platformOps.windowTitleChanges.last?.title == "example.com")
    }
}
