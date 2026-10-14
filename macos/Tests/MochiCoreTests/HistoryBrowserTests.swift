import Foundation
import Testing

@testable import MochiCore

/// The 历史记录 window's state (#108) — the foldable timeline (#116), search, deleting and opening
/// — run against a real in-memory `HistoryStore`, like the store's own tests. A row is a visit
/// (#114).
@Suite struct HistoryBrowserTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    private func makeStore() -> HistoryStore {
        let clock = clock
        return HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
    }

    /// Records a visit to `address` at `time`, optionally titled.
    @discardableResult
    private func visit(_ store: HistoryStore, _ address: String, at time: String, title: String? = nil)
        -> HistoryVisit.ID
    {
        let saved = clock.now
        clock.now = historyTestDate(time)
        let id = store.recordVisit(to: URL(string: address)!)!
        if let title { store.updateTitle(title, ofVisit: id) }
        clock.now = saved
        return id
    }

    private func makeBrowser(_ store: HistoryStore, opened: @escaping (URL) -> Void = { _ in }) -> HistoryBrowser {
        HistoryBrowser(store: store, open: opened)
    }

    private func addresses(_ days: [HistoryBrowser.Day]) -> [[String]] {
        days.map { $0.rows.map(\.url.absoluteString) }
    }

    /// A browser as the window has it on opening: every day folded but 今天.
    private func openedBrowser(_ store: HistoryStore, opened: @escaping (URL) -> Void = { _ in }) -> HistoryBrowser {
        let browser = makeBrowser(store, opened: opened)
        browser.resetExpansion()
        return browser
    }

    /// Unfolds every day — for the tests about what a day lists rather than about folding.
    private func expandAll(_ browser: HistoryBrowser) {
        for day in browser.days where !day.isExpanded { browser.setExpanded(true, day: day.day) }
    }

    // MARK: The timeline (#116)

    @Test func daysAreListedNewestFirstWithHowManyVisitsEach() {
        let store = makeStore()
        visit(store, "https://example.com/old", at: "2026-10-10 09:00")
        visit(store, "https://example.com/yesterday-early", at: "2026-10-11 08:00")
        visit(store, "https://example.com/today", at: "2026-10-12 09:30")
        visit(store, "https://example.com/yesterday-late", at: "2026-10-11 23:59")

        let days = openedBrowser(store).days

        #expect(days.map(\.day) == ["2026-10-12", "2026-10-11", "2026-10-10"].map { historyTestDate("\($0) 00:00") })
        #expect(days.map(\.visits) == [1, 2, 1])
    }

    /// The window opens on today alone: the past is folded away.
    @Test func openingUnfoldsTodayAndFoldsTheRest() {
        let store = makeStore()
        visit(store, "https://example.com/yesterday", at: "2026-10-11 09:00")
        visit(store, "https://example.com/today", at: "2026-10-12 09:00")

        let days = openedBrowser(store).days

        #expect(days.map(\.isExpanded) == [true, false])
        #expect(addresses(days) == [["https://example.com/today"], []])
    }

    @Test func withNothingTodayEveryDayIsFolded() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-11 09:00")
        visit(store, "https://example.com/b", at: "2026-10-09 09:00")

        let days = openedBrowser(store).days

        #expect(days.map(\.isExpanded) == [false, false])
        #expect(days.allSatisfy { $0.rows.isEmpty })
        #expect(days.map(\.visits) == [1, 1])
    }

    @Test func aDayUnfoldsAndFoldsAgain() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-11 09:00")
        visit(store, "https://example.com/b", at: "2026-10-11 09:05")
        let browser = openedBrowser(store)
        let yesterday = browser.days[0].day

        browser.setExpanded(true, day: yesterday)
        #expect(addresses(browser.days) == [["https://example.com/b", "https://example.com/a"]])

        browser.setExpanded(false, day: yesterday)
        #expect(addresses(browser.days) == [[]])
    }

    /// Coming back to the window re-reads the store but leaves what the user unfolded alone.
    @Test func reloadingKeepsWhatIsUnfolded() {
        let store = makeStore()
        visit(store, "https://example.com/old", at: "2026-10-10 09:00")
        visit(store, "https://example.com/today", at: "2026-10-12 09:00")
        let browser = openedBrowser(store)
        browser.setExpanded(true, day: browser.days[1].day)
        browser.setExpanded(false, day: browser.days[0].day)
        visit(store, "https://example.com/meanwhile", at: "2026-10-12 09:59")

        browser.reload()

        #expect(browser.days.map(\.isExpanded) == [false, true])
        #expect(browser.days.map(\.visits) == [2, 1])
    }

    /// ⌘Y again: back to today alone, whatever was unfolded before.
    @Test func reopeningFoldsEverythingButTodayAgain() {
        let store = makeStore()
        visit(store, "https://example.com/old", at: "2026-10-10 09:00")
        visit(store, "https://example.com/today", at: "2026-10-12 09:00")
        let browser = openedBrowser(store)
        browser.setExpanded(true, day: browser.days[1].day)

        browser.resetExpansion()

        #expect(browser.days.map(\.isExpanded) == [true, false])
    }

    /// Open across midnight: the new 今天 is unfolded, the day that just ended stays as it was.
    @Test func pastMidnightTheNewTodayUnfolds() {
        let store = makeStore()
        visit(store, "https://example.com/before", at: "2026-10-11 09:00")
        visit(store, "https://example.com/late", at: "2026-10-12 23:00")
        let browser = openedBrowser(store)
        clock.now = historyTestDate("2026-10-13 00:05")
        visit(store, "https://example.com/after-midnight", at: "2026-10-13 00:01")

        browser.reload()

        #expect(browser.days.map(\.title).first?.hasPrefix("今天") == true)
        #expect(browser.days.map(\.isExpanded) == [true, true, false])
    }

    /// A timeline, not a list of addresses: going back and forth between two pages lists every
    /// visit, in the order they happened.
    @Test func everyVisitIsARowInTheOrderTheyHappened() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        visit(store, "https://example.com/b", at: "2026-10-12 09:01")
        visit(store, "https://example.com/a", at: "2026-10-12 09:02")
        visit(store, "https://example.com/a", at: "2026-10-10 09:00")
        let browser = openedBrowser(store)

        expandAll(browser)

        #expect(
            addresses(browser.days) == [
                ["https://example.com/a", "https://example.com/b", "https://example.com/a"],
                ["https://example.com/a"],
            ])
        #expect(browser.days[0].rows.map(\.time) == ["09:02", "09:01", "09:00"])
    }

    @Test(arguments: [
        (visited: "2026-10-12 00:00", title: "今天 · 10月12日 星期一"),
        (visited: "2026-10-11 23:59", title: "昨天 · 10月11日 星期日"),
        (visited: "2026-10-10 12:00", title: "10月10日 星期六"),
        (visited: "2025-12-31 12:00", title: "2025年12月31日 星期三"),
    ])
    func daysAreNamedAfterTheirDate(_ row: (visited: String, title: String)) {
        let store = makeStore()
        visit(store, "https://example.com/a", at: row.visited)

        #expect(openedBrowser(store).days.map(\.title) == [row.title])
    }

    /// 今天 is the store's today: once its clock passes midnight, yesterday's visits are 昨天.
    @Test func theDaysFollowTheStoresNow() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 23:00")
        let browser = openedBrowser(store)
        #expect(browser.days.map(\.title) == ["今天 · 10月12日 星期一"])

        clock.now = historyTestDate("2026-10-13 00:01")
        browser.reload()

        #expect(browser.days.map(\.title) == ["昨天 · 10月12日 星期一"])
    }

    @Test func aRowShowsItsTitleWithTheAddressBelowAndTheTimeVisited() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:05", title: "  Page\n  A ")

        let row = openedBrowser(store).days.first?.rows.first

        #expect(row?.title == "Page A")
        #expect(row?.subtitle == "https://example.com/a")
        #expect(row?.time == "09:05")
    }

    /// No title yet: the address stands in for it, and isn't repeated underneath.
    @Test(arguments: [nil, "   "] as [String?])
    func anUntitledRowShowsItsAddress(_ title: String?) {
        let store = makeStore()
        visit(store, "https://example.com/untitled", at: "2026-10-12 09:00", title: title)

        let row = openedBrowser(store).days.first?.rows.first

        #expect(row?.title == "https://example.com/untitled")
        #expect(row?.subtitle == nil)
    }

    /// #117: a row shows its own visit's icon, read from the store.
    @Test func aRowCarriesItsVisitsIcon() throws {
        let store = makeStore()
        let icon = Data("png".utf8)
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: URL(string: "https://example.com/a")!, favicon: icon)
        clock.now = historyTestDate("2026-10-12 10:00")
        visit(store, "https://example.com/b", at: "2026-10-12 09:30")
        let browser = openedBrowser(store)

        let rows = try #require(browser.days.first?.rows)

        #expect(rows.map { $0.faviconID.flatMap(browser.favicon) } == [nil, icon])
    }

    @Test func anEmptyHistoryHasNoDays() {
        #expect(openedBrowser(makeStore()).days.isEmpty)
    }

    // MARK: Search (#118)

    @Test(arguments: [
        (query: "Cats", shown: ["https://video.example.com/watch"]),
        (query: "cats", shown: ["https://video.example.com/watch"]),
        (query: "news.example", shown: ["https://news.example.org/today"]),
        (query: " news ", shown: ["https://news.example.org/today"]),
        (query: "example", shown: ["https://video.example.com/watch", "https://news.example.org/today"]),
        (query: "nothing like it", shown: []),
    ])
    func searchMatchesTitleOrAddress(_ row: (query: String, shown: [String])) {
        let store = makeStore()
        visit(store, "https://news.example.org/today", at: "2026-10-01 09:00", title: "Headlines")
        visit(store, "https://video.example.com/watch", at: "2026-10-12 09:00", title: "Funny Cats")
        let browser = openedBrowser(store)

        browser.search(row.query)

        #expect(browser.isSearching)
        #expect(browser.shownRows.map(\.url.absoluteString) == row.shown)
        #expect(browser.days.isEmpty)
    }

    /// Search results are one flat timeline, folded days and all — no day headers — with how many
    /// there are.
    @Test func searchResultsAreOneFlatTimelineWithTheirCount() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        visit(store, "https://example.com/b", at: "2026-10-10 09:00")
        visit(store, "https://example.com/c", at: "2026-10-12 09:30")
        visit(store, "https://other.org/", at: "2026-10-11 09:00")
        let browser = openedBrowser(store)

        browser.search("example.com")

        #expect(
            browser.results.map(\.url.path) == ["/c", "/a", "/b"])
        #expect(browser.matchCount == 3)
    }

    /// With no day header above it, a result says which day it is from as well as when.
    @Test func aResultsTimeSaysTheDayToo() {
        let store = makeStore()
        visit(store, "https://example.com/today", at: "2026-10-12 09:05")
        visit(store, "https://example.com/yesterday", at: "2026-10-11 21:30")
        visit(store, "https://example.com/earlier", at: "2026-10-04 08:00")
        visit(store, "https://example.com/last-year", at: "2025-12-31 23:59")
        let browser = openedBrowser(store)

        browser.search("example")

        #expect(
            browser.results.map(\.time) == [
                "今天 · 10月12日 星期一 09:05", "昨天 · 10月11日 星期日 21:30", "10月4日 星期日 08:00",
                "2025年12月31日 星期三 23:59",
            ])
    }

    /// Leaving a search goes back to the timeline as it was before it.
    @Test func clearingTheSearchRestoresWhatWasUnfolded() {
        let store = makeStore()
        visit(store, "https://example.com/old", at: "2026-10-10 09:00")
        visit(store, "https://example.com/today", at: "2026-10-12 09:00")
        let browser = openedBrowser(store)
        browser.setExpanded(true, day: browser.days[1].day)
        browser.setExpanded(false, day: browser.days[0].day)

        browser.search("example")
        browser.search("")

        #expect(browser.days.map(\.isExpanded) == [false, true])
    }

    /// Only whitespace is no search: the timeline, as it was.
    @Test(arguments: ["", "   "])
    func aBlankQueryIsTheTimeline(_ query: String) {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        let browser = openedBrowser(store)

        browser.search(query)

        #expect(!browser.isSearching)
        #expect(browser.results.isEmpty)
        #expect(addresses(browser.days) == [["https://example.com/a"]])
    }

    /// `site:<host>` at the start narrows to that host exactly, whatever its case; what follows
    /// it narrows further.
    @Test(arguments: [
        (query: "site:knitpeople.com", shown: ["https://knitpeople.com/b", "https://knitpeople.com/a"]),
        (query: "SITE:KnitPeople.com", shown: ["https://knitpeople.com/b", "https://knitpeople.com/a"]),
        (query: "  site:knitpeople.com  ", shown: ["https://knitpeople.com/b", "https://knitpeople.com/a"]),
        (query: "site:www.knitpeople.com", shown: ["https://www.knitpeople.com/"]),
        (query: "site:knitpeople.com 薪酬", shown: ["https://knitpeople.com/a"]),
        (query: "site:knitpeople.com   薪酬  ", shown: ["https://knitpeople.com/a"]),
        // Pasted with its scheme or path, it is still the host that counts.
        (query: "site:https://knitpeople.com/whatever", shown: ["https://knitpeople.com/b", "https://knitpeople.com/a"]),
        (query: "site:knitpeople.com/whatever", shown: ["https://knitpeople.com/b", "https://knitpeople.com/a"]),
        // `site:` anywhere but the start is just text.
        (query: "薪酬 site:knitpeople.com", shown: []),
    ])
    func siteNarrowsToOneHost(_ row: (query: String, shown: [String])) {
        let store = makeStore()
        visit(store, "https://knitpeople.com/a", at: "2026-10-12 09:00", title: "薪酬报告")
        visit(store, "https://www.knitpeople.com/", at: "2026-10-12 09:01", title: "薪酬报告")
        visit(store, "https://knitpeople.com.cn/", at: "2026-10-12 09:02", title: "薪酬报告")
        visit(store, "https://knitpeople.com/b", at: "2026-10-12 09:03", title: "其他")
        let browser = openedBrowser(store)

        browser.search(row.query)

        #expect(browser.results.map(\.url.absoluteString) == row.shown)
    }

    /// Deleting while searching takes the result off at once, and the count with it.
    @Test func deletingAResultUpdatesTheCount() {
        let store = makeStore()
        let a = visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        visit(store, "https://example.com/b", at: "2026-10-11 09:00")
        let browser = openedBrowser(store)
        browser.search("example")

        browser.delete([a])

        #expect(browser.results.map(\.url.path) == ["/b"])
        #expect(browser.matchCount == 1)
    }

    // MARK: The context menu (#119)

    /// 拷贝 and 显示此网站的所有记录 are about one page: only with one row selected.
    @Test(arguments: [
        (selected: 0, available: false),
        (selected: 1, available: true),
        (selected: 2, available: false),
    ])
    func copyingAndShowingTheSiteNeedOneRow(_ row: (selected: Int, available: Bool)) {
        let store = makeStore()
        let a = visit(store, "https://www.example.com/a", at: "2026-10-12 09:00")
        let b = visit(store, "https://www.example.com/b", at: "2026-10-12 09:01")
        let browser = openedBrowser(store)
        let selection = Set([a, b].prefix(row.selected))

        #expect((browser.copiedText(for: selection) != nil) == row.available)
        #expect((browser.siteQuery(for: selection) != nil) == row.available)
    }

    @Test func copyingGivesTheWholeAddress() {
        let store = makeStore()
        let a = visit(store, "https://www.example.com/watch?v=1&t=30", at: "2026-10-12 09:00", title: "A video")
        let browser = openedBrowser(store)

        #expect(browser.copiedText(for: [a]) == "https://www.example.com/watch?v=1&t=30")
    }

    /// 显示此网站的所有记录 searches for the row's host, and that search finds exactly the host's
    /// visits.
    @Test func showingTheSiteSearchesForItsHost() throws {
        let store = makeStore()
        let a = visit(store, "https://WWW.Example.com/a", at: "2026-10-12 09:00")
        visit(store, "https://www.example.com/b", at: "2026-10-11 09:00")
        visit(store, "https://example.com/c", at: "2026-10-11 09:30")
        let browser = openedBrowser(store)

        let query = try #require(browser.siteQuery(for: [a]))
        browser.search(query)

        #expect(query == "site:www.example.com")
        #expect(browser.results.map(\.url.path) == ["/a", "/b"])
    }

    /// A row that is no longer on show (deleted meanwhile) offers neither.
    @Test func aRowNoLongerShownOffersNothing() {
        let store = makeStore()
        let a = visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        let browser = openedBrowser(store)
        browser.delete([a])

        #expect(browser.copiedText(for: [a]) == nil)
        #expect(browser.siteQuery(for: [a]) == nil)
    }

    // MARK: Deleting

    @Test func deletingSelectedRowsRemovesThoseVisitsFromTheStore() {
        let store = makeStore()
        let a = visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        visit(store, "https://example.com/b", at: "2026-10-12 09:01")
        let c = visit(store, "https://example.com/c", at: "2026-10-11 09:00")
        let browser = openedBrowser(store)

        browser.delete([a, c])

        #expect(store.visits(since: .distantPast).map(\.url.absoluteString) == ["https://example.com/b"])
        #expect(addresses(browser.days) == [["https://example.com/b"]])
    }

    /// Deleting a row is deleting that visit: the page's other visits stay on the timeline.
    @Test func deletingOneVisitKeepsTheOtherVisitsToThatPage() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-11 09:00")
        let today = visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        let browser = openedBrowser(store)

        browser.delete([today])

        #expect(browser.days.map(\.title) == ["昨天 · 10月11日 星期日"])
        #expect(browser.days.map(\.visits) == [1])
    }

    @Test func deletingADayRemovesEverythingFromThatDayOnly() {
        let store = makeStore()
        visit(store, "https://example.com/today", at: "2026-10-12 00:00")
        visit(store, "https://example.com/late", at: "2026-10-11 23:59")
        visit(store, "https://example.com/early", at: "2026-10-11 00:00")
        visit(store, "https://example.com/before", at: "2026-10-10 23:59")
        let browser = openedBrowser(store)

        browser.deleteDay(browser.days[1].day)

        #expect(
            store.visits(since: .distantPast).map(\.url.absoluteString)
                == ["https://example.com/today", "https://example.com/before"])
        #expect(browser.days.count == 2)
    }

    // MARK: 清除历史记录… (ADR-0032)

    /// The window's own clearing: every visit within the range, counted back from the store's now,
    /// and history alone — nothing else is touched, so there is nothing else to test for here.
    @Test(arguments: [
        (range: BrowsingDataTimeRange.pastHour, kept: ["/two-hours-ago", "/yesterday"]),
        (range: .past24Hours, kept: ["/yesterday"]),
        (range: .allTime, kept: []),
    ])
    func clearingRemovesTheVisitsWithinTheRange(_ row: (range: BrowsingDataTimeRange, kept: [String])) {
        let store = makeStore()
        visit(store, "https://example.com/yesterday", at: "2026-10-11 09:00")
        visit(store, "https://example.com/two-hours-ago", at: "2026-10-12 08:00")
        visit(store, "https://example.com/half-an-hour-ago", at: "2026-10-12 09:30")
        let browser = openedBrowser(store)

        browser.clearHistory(from: row.range)

        #expect(store.visits(since: .distantPast).map(\.url.path) == row.kept)
        #expect(browser.days.map(\.visits).reduce(0, +) == row.kept.count)
    }

    // MARK: Opening

    @Test func openingHandsTheAddressOn() {
        let store = makeStore()
        let a = visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        var opened: [URL] = []
        let browser = openedBrowser(store) { opened.append($0) }

        browser.open([a])

        #expect(opened == [URL(string: "https://example.com/a")!])
    }

    /// 打开 is about one page, like 拷贝: with several rows selected the context menu's 打开 is
    /// greyed out and Return opens nothing — there is one widget, and picking one of them for the
    /// user would be a guess. (A double-click is different: it says which row; see below.)
    @Test func openingSeveralOpensNothing() {
        let store = makeStore()
        let older = visit(store, "https://example.com/older", at: "2026-10-11 09:00")
        let newer = visit(store, "https://example.com/newer", at: "2026-10-12 09:00")
        visit(store, "https://example.com/newest", at: "2026-10-12 09:30")
        var opened: [URL] = []
        let browser = openedBrowser(store) { opened.append($0) }
        expandAll(browser)

        browser.open([older, newer])

        #expect(opened.isEmpty)
        #expect(!browser.canOpen([older, newer]))
        #expect(browser.canOpen([newer]))
    }

    /// A double-click opens the row it hit, even among several selected — and leaves that row alone
    /// selected, so what is selected is what was opened.
    @Test func aDoubleClickOpensTheRowItHitAndSelectsItAlone() {
        let store = makeStore()
        let older = visit(store, "https://example.com/older", at: "2026-10-12 09:00")
        let newer = visit(store, "https://example.com/newer", at: "2026-10-12 09:30")
        var opened: [URL] = []
        let browser = openedBrowser(store) { opened.append($0) }

        let selection = browser.activate([older, newer], hitRow: older)

        #expect(opened == [URL(string: "https://example.com/older")!])
        #expect(selection == [older])
    }

    /// Return hits no row: it opens the selection when that is one row, and nothing otherwise.
    @Test(arguments: [1, 2])
    func returnOpensOnlyASingleRow(_ selected: Int) {
        let store = makeStore()
        let a = visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        let b = visit(store, "https://example.com/b", at: "2026-10-12 09:30")
        var opened: [URL] = []
        let browser = openedBrowser(store) { opened.append($0) }
        let before = Set([a, b].prefix(selected))

        let after = browser.activate(before, hitRow: nil)

        #expect(opened == (selected == 1 ? [URL(string: "https://example.com/a")!] : []))
        #expect(after == before)
    }

    /// A visit folded away or deleted isn't on show, so it can't be opened.
    @Test func openingNothingShownOpensNothing() {
        let store = makeStore()
        let folded = visit(store, "https://example.com/folded", at: "2026-10-11 09:00")
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        var opened: [URL] = []
        let browser = openedBrowser(store) { opened.append($0) }

        browser.open([])
        browser.open([999])
        browser.open([folded])

        #expect(opened.isEmpty)
    }
}
