import Foundation
import Testing

@testable import MochiCore

/// 历史记录 (#102): which of the widget's main-page address changes `Orchestrator` records, where
/// titles land, and opening a page from the menu.
@Suite struct OrchestratorHistoryTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    private func makeOrchestrator(
        config: WidgetConfig = WidgetConfig(url: URL(string: "https://start.example.com")!)
    ) -> (FakePlatformOps, Orchestrator, HistoryStore) {
        let fake = FakePlatformOps()
        let clock = clock
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config }, historyStore: store)
        orchestrator.start()
        return (fake, orchestrator, store)
    }

    private func recorded(_ store: HistoryStore) -> [String] {
        store.visits(since: .distantPast).map(\.url.absoluteString)
    }

    // MARK: What gets recorded

    @Test(arguments: [
        (address: "https://example.com/a", isRecorded: true),
        (address: "http://example.com/a", isRecorded: true),
        (address: "HTTPS://EXAMPLE.COM/a", isRecorded: true),
        (address: "data:text/html,<p>hi</p>", isRecorded: false),
        (address: "about:blank", isRecorded: false),
        (address: "file:///Users/someone/page.html", isRecorded: false),
        (address: "blob:https://example.com/123", isRecorded: false),
    ])
    func onlyWebPagesAreRecorded(_ row: (address: String, isRecorded: Bool)) {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateMainFrameURLChanged(URL(string: row.address)!)

        #expect(recorded(store) == (row.isRecorded ? [row.address] : []))
    }

    /// Each in-page address change is a visit — a video site switching videos without loading a
    /// new document.
    @Test func everyMainPageAddressChangeIsAVisit() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateMainFrameURLChanged(URL(string: "https://youtube.com/watch?v=1")!)
        clock.now = clock.now.addingTimeInterval(60)
        fake.simulateMainFrameURLChanged(URL(string: "https://youtube.com/watch?v=2")!)

        #expect(recorded(store) == ["https://youtube.com/watch?v=2", "https://youtube.com/watch?v=1"])
    }

    @Test func nothingIsRecordedWhileTheEmptyPageIsUp() {
        let (fake, orchestrator, store) = makeOrchestrator(config: WidgetConfig(url: nil))
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateEmptyPageVisibilityChanged(true)
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/behind")!)
        #expect(recorded(store).isEmpty)

        fake.simulateEmptyPageVisibilityChanged(false)
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/next")!)
        #expect(recorded(store) == ["https://example.com/next"])
    }

    @Test func ghostModeVisitsAreRecordedToo() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/autoplay-next")!)

        #expect(recorded(store) == ["https://example.com/autoplay-next"])
    }

    /// Popup Windows (OAuth hops and the like) never reach history: only the widget's own page is
    /// listened to.
    @Test func onlyTheWidgetsPageIsListenedTo() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        let popup = NewWindowRequest(trigger: .script, opener: .widget, url: URL(string: "https://login.example.com")!)
        #expect(fake.simulateNewWindowRequested(popup) == .openPopupWindow)

        #expect(fake.mainFrameURLChangeRegistrations == [1])
    }

    @Test func aReopenedWidgetIsRecordedToo() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        orchestrator.closeWidget()
        orchestrator.openWidget()
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/again")!, windowID: 2)

        #expect(recorded(store) == ["https://example.com/again"])
    }

    // MARK: Titles

    @Test func thePagesTitleLandsOnItsVisit() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/b")!)

        fake.simulatePageTitleChanged("Page B")

        #expect(store.visits(since: .distantPast).map(\.title) == ["Page B", nil])
    }

    /// #114: a page visited again is a new visit, and its title lands on that visit alone — what
    /// the page was called the first time stays on the first visit.
    @Test func aRevisitsTitleLeavesTheEarlierVisitAlone() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)
        fake.simulatePageTitleChanged("Old title")
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/b")!)
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)

        fake.simulatePageTitleChanged("New title")

        #expect(recorded(store) == ["https://example.com/a", "https://example.com/b", "https://example.com/a"])
        #expect(store.visits(since: .distantPast).map(\.title) == ["New title", nil, "Old title"])
    }

    /// A title change still drives the window title — history listens alongside, not instead.
    @Test func theWindowTitleStillFollowsThePage() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)

        fake.simulatePageTitleChanged("Page A")

        #expect(fake.windowTitleChanges.last?.title == "Page A")
    }

    /// The title of a page that isn't recorded must not be pinned on the one before it.
    @Test func aTitleAfterAnUnrecordedAddressGoesNowhere() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)
        fake.simulatePageTitleChanged("Page A")

        fake.simulateMainFrameURLChanged(URL(string: "about:blank")!)
        fake.simulatePageTitleChanged("Blank")

        #expect(store.visits(since: .distantPast).map(\.title) == ["Page A"])
    }

    @Test(arguments: [nil, "", "   "] as [String?])
    func aMissingTitleKeepsTheOneAlreadyThere(_ title: String?) {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)
        fake.simulatePageTitleChanged("Page A")

        fake.simulatePageTitleChanged(title)

        #expect(store.visits(since: .distantPast).map(\.title) == ["Page A"])
    }

    // MARK: Site icons (#117)

    private let iconA = Data("icon of a.example.com".utf8)
    private let iconB = Data("icon of b.example.com".utf8)

    private func icons(_ store: HistoryStore) -> [Data?] {
        store.visits(since: .distantPast).map { $0.faviconID.flatMap(store.favicon) }
    }

    /// The icon is fetched once the page has loaded, after its visit was recorded: it is written
    /// to that visit.
    @Test func anIconLandsOnTheVisitOfItsPage() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/one")!)

        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/one")!)

        #expect(icons(store) == [iconA])
    }

    /// A video site switching videos in the page records a visit but loads nothing: the new visit
    /// takes the icon its site already has.
    @Test func aVisitWithinTheSameSiteTakesItsIconRightAway() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/watch?v=1")!)
        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/watch?v=1")!)

        fake.simulateMainFrameURLChanged(URL(string: "https://A.EXAMPLE.COM/watch?v=2")!)

        #expect(icons(store) == [iconA, iconA])
    }

    /// Moving to another site never carries the last site's icon along: the new visit waits for
    /// its own.
    @Test func aVisitToAnotherSiteWaitsForItsOwnIcon() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/")!)
        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/")!)

        fake.simulateMainFrameURLChanged(URL(string: "https://b.example.com/")!)
        #expect(icons(store) == [nil, iconA])

        fake.simulateSiteIconLoaded(iconB, for: URL(string: "https://b.example.com/")!)
        #expect(icons(store) == [iconB, iconA])
    }

    /// A slow icon that arrives once the page has moved to another site is dropped: it isn't the
    /// current visit's.
    @Test func aLateIconFromTheSiteLeftBehindIsDropped() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/")!)
        fake.simulateMainFrameURLChanged(URL(string: "https://b.example.com/")!)

        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/")!)

        #expect(icons(store) == [nil, nil])
    }

    /// Nothing recorded, nothing to give an icon to — nor does the last visit get it.
    @Test func anIconForAnUnrecordedPageGoesNowhere() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/")!)
        fake.simulateMainFrameURLChanged(URL(string: "about:blank")!)

        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/")!)

        #expect(icons(store) == [nil])
    }

    @Test func ghostModeVisitsGetTheirIconsToo() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/next")!)

        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/next")!)

        #expect(icons(store) == [iconA])
    }

    /// The menu shows each visit's own icon.
    @Test func theMenuCarriesEachVisitsIcon() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://a.example.com/")!)
        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://a.example.com/")!)
        fake.simulateMainFrameURLChanged(URL(string: "https://b.example.com/")!)

        let items = orchestrator.historyMenu().today

        #expect(items.map { $0.faviconID.flatMap(orchestrator.historyFavicon) } == [nil, iconA])
        #expect(items.map { $0.faviconID.flatMap(store.favicon) } == [nil, iconA])
    }

    // MARK: The menu

    @Test func theMenuIsBuiltFromTheStoreAtTheStoresNow() {
        let (fake, orchestrator, _) = makeOrchestrator()
        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/today")!)
        fake.simulatePageTitleChanged("Today")
        clock.now = historyTestDate("2026-10-13 09:00")

        let menu = orchestrator.historyMenu()

        #expect(menu.today.isEmpty)
        #expect(menu.earlierDays.map { $0.items.map(\.title) } == [["Today"]])
    }

    @Test func withoutAStoreTheMenuIsEmptyAndNothingBreaks() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig() })
        orchestrator.start()

        fake.simulateMainFrameURLChanged(URL(string: "https://example.com/a")!)

        #expect(orchestrator.historyMenu() == HistoryMenu(today: [], earlierDays: []))
    }

    // MARK: Opening from history

    private let historyURL = URL(string: "https://example.com/from-history")!

    @Test func openingFromHistoryLoadsInTheOpenWidget() {
        let (fake, orchestrator, _) = makeOrchestrator()

        orchestrator.openFromHistory(historyURL)

        #expect(fake.createdFrames.count == 1)
        #expect(fake.loadedURLs.last?.url == historyURL)
        #expect(fake.loadedURLs.last?.windowID == 1)
    }

    /// The reopened widget goes straight to the page picked: the startup page is never loaded on
    /// the way, so it is neither shown nor recorded as a visit (#102, #108).
    @Test(arguments: [
        (name: "startup URL", config: WidgetConfig(url: URL(string: "https://start.example.com")!)),
        (name: "Empty Page", config: WidgetConfig(url: nil).updatingStartupTarget(.emptyPage)),
    ])
    func openingFromHistoryWithTheWidgetClosedLoadsOnlyThatPage(_ row: (name: String, config: WidgetConfig)) {
        let (fake, orchestrator, _) = makeOrchestrator(config: row.config)
        orchestrator.closeWidget()

        orchestrator.openFromHistory(historyURL)

        #expect(fake.createdFrames.count == 2)
        #expect(fake.loadedURLs.filter { $0.windowID == 2 }.map(\.url) == [historyURL])
        #expect(!fake.emptyPageShownWindowIDs.contains(2))
    }

    /// Like typing the address: it becomes the page last visited.
    @Test func openingFromHistoryWithTheWidgetClosedRemembersThePage() {
        let fake = FakePlatformOps()
        var persisted: [URL] = []
        let orchestrator = Orchestrator(
            platformOps: fake, currentConfig: { WidgetConfig(url: URL(string: "https://start.example.com")!) },
            persistURL: { persisted.append($0) })
        orchestrator.start()
        orchestrator.closeWidget()

        orchestrator.openFromHistory(historyURL)

        #expect(persisted == [historyURL])
    }

    /// An explicit choice from history: a Ghost Mode widget follows it without leaving Ghost Mode —
    /// only the hotkey and the tray decide that.
    @Test func openingFromHistoryInGhostModeStaysInGhostMode() {
        let (fake, orchestrator, _) = makeOrchestrator()
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        orchestrator.openFromHistory(historyURL)

        #expect(fake.loadedURLs.last?.url == historyURL)
        #expect(fake.trayItem("幽灵模式").isChecked())
        #expect(fake.shownWindowIDs == [1])
    }

    // MARK: 移除历史记录项目 (#110)

    /// What expired while Mochi wasn't running goes at launch.
    @Test(arguments: [
        (retention: HistoryRetention.oneWeek, kept: ["/2-days"]),
        (retention: .manual, kept: ["/2-days", "/2-weeks"]),
    ])
    func launchRemovesWhatIsPastTheRetention(_ row: (retention: HistoryRetention, kept: [String])) {
        let clock = clock
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        clock.now = historyTestDate("2026-09-28 09:00")
        store.recordVisit(to: URL(string: "https://example.com/2-weeks")!)
        clock.now = historyTestDate("2026-10-10 09:00")
        store.recordVisit(to: URL(string: "https://example.com/2-days")!)
        clock.now = historyTestDate("2026-10-12 10:00")
        let config = WidgetConfig(url: URL(string: "https://start.example.com")!).updatingHistoryRetention(row.retention)
        let orchestrator = Orchestrator(platformOps: FakePlatformOps(), currentConfig: { config }, historyStore: store)

        orchestrator.start()

        #expect(store.visits(since: .distantPast).map(\.url.path) == row.kept)
    }
}
