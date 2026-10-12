import Foundation
import Testing

@testable import MochiCore

/// The 历史记录 window's way into the rest of the app (#108): `Orchestrator.makeHistoryBrowser()`
/// opens through `openFromHistory` and deletes from the same store the 历史记录 menu reads.
@Suite struct OrchestratorHistoryWindowTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))
    private let page = URL(string: "https://example.com/from-the-window")!

    private func makeOrchestrator() -> (FakePlatformOps, Orchestrator, HistoryStore) {
        let fake = FakePlatformOps()
        let clock = clock
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        let orchestrator = Orchestrator(
            platformOps: fake, currentConfig: { WidgetConfig(url: URL(string: "https://start.example.com")!) },
            historyStore: store)
        orchestrator.start()
        return (fake, orchestrator, store)
    }

    @Test func withoutAStoreThereIsNoWindowToShow() {
        let orchestrator = Orchestrator(platformOps: FakePlatformOps(), currentConfig: { WidgetConfig() })

        #expect(orchestrator.makeHistoryBrowser() == nil)
    }

    @Test func aDoubleClickLoadsInTheOpenWidget() throws {
        let (fake, orchestrator, _) = makeOrchestrator()
        let browser = try #require(orchestrator.makeHistoryBrowser())

        browser.open([page], shownIn: [section(with: page)])

        #expect(fake.createdFrames.count == 1)
        #expect(fake.loadedURLs.last?.url == page)
        #expect(fake.loadedURLs.last?.windowID == 1)
    }

    @Test func aDoubleClickWithTheWidgetClosedReopensItFirst() throws {
        let (fake, orchestrator, _) = makeOrchestrator()
        let browser = try #require(orchestrator.makeHistoryBrowser())
        orchestrator.closeWidget()

        browser.open([page], shownIn: [section(with: page)])

        #expect(fake.createdFrames.count == 2)
        #expect(fake.loadedURLs.last?.url == page)
        #expect(fake.loadedURLs.last?.windowID == 2)
    }

    /// The window stays open next to a Ghost Mode widget; a double-click there moves the widget
    /// on without bringing it out of Ghost Mode.
    @Test func aDoubleClickInGhostModeStaysInGhostMode() throws {
        let (fake, orchestrator, _) = makeOrchestrator()
        let browser = try #require(orchestrator.makeHistoryBrowser())
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        browser.open([page], shownIn: [section(with: page)])

        #expect(fake.loadedURLs.last?.url == page)
        #expect(fake.trayItem("幽灵模式").isChecked())
        #expect(fake.shownWindowIDs == [1])
    }

    /// The menu is rebuilt from the store each time it opens, so a page deleted in the window is
    /// gone from the menu too.
    @Test func whatTheWindowDeletesLeavesTheMenu() throws {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/keep")!)
        fake.simulateMainFrameURLChanged(page)
        let browser = try #require(orchestrator.makeHistoryBrowser())

        browser.delete([page])

        #expect(orchestrator.historyMenu().today.map(\.url) == [URL(string: "https://example.com/keep")!])
    }

    @Test func aDeletedDayLeavesTheMenu() throws {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(page)
        clock.now = historyTestDate("2026-10-13 09:00")
        let browser = try #require(orchestrator.makeHistoryBrowser())
        #expect(orchestrator.historyMenu().earlierDays.count == 1)

        browser.deleteDay(browser.sections(matching: "")[0].day)

        #expect(orchestrator.historyMenu().earlierDays.isEmpty)
    }

    private func section(with url: URL) -> HistoryBrowser.Section {
        HistoryBrowser.Section(
            day: historyTestDate("2026-10-12 00:00"), title: "今天",
            rows: [HistoryBrowser.Row(url: url, title: url.absoluteString, subtitle: nil, time: "09:00")])
    }
}
