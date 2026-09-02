import Foundation
import Testing

@testable import MochiCore

@Suite struct WindowPlacementTests {
    @Test func keepsPersistedFrameWhenItIntersectsAScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let persisted = WindowFrame(x: 100, y: 100, width: 800, height: 600)

        let resolved = WindowPlacement.resolve(persisted: persisted, visibleScreens: screens)

        #expect(resolved == persisted)
    }

    @Test func keepsPersistedFrameWhenItOnlyPartiallyOverlapsAScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let persisted = WindowFrame(x: 1400, y: 0, width: 800, height: 600)

        let resolved = WindowPlacement.resolve(persisted: persisted, visibleScreens: screens)

        #expect(resolved == persisted)
    }

    @Test func recoversToSafeDefaultWhenPersistedFrameIsOutsideAllScreens() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let persisted = WindowFrame(x: 10_000, y: 10_000, width: 800, height: 600)

        let resolved = WindowPlacement.resolve(persisted: persisted, visibleScreens: [primary, secondary])

        #expect(resolved == WindowPlacement.safeDefault(in: primary))
    }

    @Test func usesSafeDefaultWhenNoPersistedFrameExists() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let resolved = WindowPlacement.resolve(persisted: nil, visibleScreens: [primary])

        #expect(resolved == WindowPlacement.safeDefault(in: primary))
    }

    @Test func fallsBackToBareDefaultWhenNoScreensAreReported() {
        let resolved = WindowPlacement.resolve(persisted: nil, visibleScreens: [])

        #expect(resolved == WindowFrame(x: 0, y: 0, width: WindowPlacement.defaultWidth, height: WindowPlacement.defaultHeight))
    }

    @Test func safeDefaultIsCenteredOnThePrimaryScreen() {
        let primary = CGRect(x: 100, y: 200, width: 1440, height: 900)

        let resolved = WindowPlacement.safeDefault(in: primary)

        #expect(resolved.width == WindowPlacement.defaultWidth)
        #expect(resolved.height == WindowPlacement.defaultHeight)
        #expect(resolved.x == primary.minX + (primary.width - WindowPlacement.defaultWidth) / 2)
        #expect(resolved.y == primary.minY + (primary.height - WindowPlacement.defaultHeight) / 2)
    }

    @Test func safeDefaultShrinksToFitASmallPrimaryScreen() {
        let smallScreen = CGRect(x: 0, y: 0, width: 600, height: 400)

        let resolved = WindowPlacement.safeDefault(in: smallScreen)

        #expect(resolved.width == 600)
        #expect(resolved.height == 400)
        #expect(resolved.x == 0)
        #expect(resolved.y == 0)
    }

    @Test func togglingSizeShrinksADefaultSizedFrameToCompact() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = WindowFrame(x: 100, y: 100, width: WindowPlacement.defaultWidth, height: WindowPlacement.defaultHeight)

        let resolved = WindowPlacement.togglingSize(current: current, in: screen)

        #expect(resolved.width == WindowPlacement.compactWidth)
        #expect(resolved.height == WindowPlacement.compactHeight)
    }

    @Test func togglingSizeGrowsACompactSizedFrameBackToDefault() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = WindowFrame(x: 100, y: 100, width: WindowPlacement.compactWidth, height: WindowPlacement.compactHeight)

        let resolved = WindowPlacement.togglingSize(current: current, in: screen)

        #expect(resolved.width == WindowPlacement.defaultWidth)
        #expect(resolved.height == WindowPlacement.defaultHeight)
    }

    @Test func togglingSizeKeepsTheFramesOriginFixed() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = WindowFrame(x: 200, y: 150, width: WindowPlacement.defaultWidth, height: WindowPlacement.defaultHeight)

        let resolved = WindowPlacement.togglingSize(current: current, in: screen)

        #expect(resolved.x == 200)
        #expect(resolved.y == 150)
    }

    @Test func togglingSizeClampsToStayWithinTheScreenWhenTheOriginIsNearTheEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = WindowFrame(x: 1200, y: 700, width: WindowPlacement.compactWidth, height: WindowPlacement.compactHeight)

        let resolved = WindowPlacement.togglingSize(current: current, in: screen)

        // CGFloat, converted explicitly — mixing bare Double and CGFloat in #expect can
        // misreport failure even when the values are actually equal (see CLAUDE.md).
        #expect(resolved.x + resolved.width <= Double(screen.maxX))
        #expect(resolved.y + resolved.height <= Double(screen.maxY))
    }
}
