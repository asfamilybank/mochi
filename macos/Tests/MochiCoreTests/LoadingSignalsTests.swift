import Foundation
import Testing

@testable import MochiCore

/// Covers #22's requirement that the Loading Progress Bar's underlying signals (loading
/// state, estimated progress) are consumable purely through `PlatformOps`'s
/// `onLoadingStateChanged`/`onLoadingProgressChanged` — a caller never needs a `WKWebView`
/// reference to observe them. `AppKitPlatformOps` forwards its own `WKWebView` KVO through
/// exactly this pair of callbacks (see `observeNavigationState` in `AppKitPlatformOps.swift`),
/// so exercising them here via `FakePlatformOps` is exercising the same seam a real consumer
/// would use.
@Suite struct LoadingSignalsTests {
    private func makeWindow(_ platformOps: FakePlatformOps) -> WidgetWindowHandle {
        platformOps.createWidgetWindow(initialFrame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func loadingStateChangesReachTheRegisteredHandler() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)
        var observedStates: [Bool] = []
        platformOps.onLoadingStateChanged(window) { observedStates.append($0) }

        platformOps.simulateLoadingStateChanged(true, windowID: 1)
        platformOps.simulateLoadingStateChanged(false, windowID: 1)

        #expect(observedStates == [true, false])
    }

    @Test func loadingProgressChangesReachTheRegisteredHandler() {
        let platformOps = FakePlatformOps()
        let window = makeWindow(platformOps)
        var observedProgress: [Double] = []
        platformOps.onLoadingProgressChanged(window) { observedProgress.append($0) }

        platformOps.simulateLoadingProgressChanged(0.25, windowID: 1)
        platformOps.simulateLoadingProgressChanged(1.0, windowID: 1)

        #expect(observedProgress == [0.25, 1.0])
    }

    @Test func signalsForOneWindowDoNotReachAnotherWindowsHandler() {
        let platformOps = FakePlatformOps()
        let firstWindow = makeWindow(platformOps)
        _ = makeWindow(platformOps)
        var observedStates: [Bool] = []
        var observedProgress: [Double] = []
        platformOps.onLoadingStateChanged(firstWindow) { observedStates.append($0) }
        platformOps.onLoadingProgressChanged(firstWindow) { observedProgress.append($0) }

        platformOps.simulateLoadingStateChanged(true, windowID: 2)
        platformOps.simulateLoadingProgressChanged(0.5, windowID: 2)

        #expect(observedStates.isEmpty)
        #expect(observedProgress.isEmpty)
    }
}
