import Foundation
import Testing

@testable import MochiCore

/// The 历史记录 window's logic (#108) — grouping, search, deleting and opening — run against a
/// real in-memory `HistoryStore`, like the store's own tests.
@Suite struct HistoryBrowserTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    private func makeStore() -> HistoryStore {
        let clock = clock
        return HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
    }

    /// Records `address` at `time`, optionally titled.
    private func visit(_ store: HistoryStore, _ address: String, at time: String, title: String? = nil) {
        let saved = clock.now
        clock.now = historyTestDate(time)
        store.recordVisit(to: URL(string: address)!)
        if let title { store.updateTitle(title, for: URL(string: address)!) }
        clock.now = saved
    }

    private func makeBrowser(_ store: HistoryStore, opened: @escaping (URL) -> Void = { _ in }) -> HistoryBrowser {
        HistoryBrowser(store: store, open: opened)
    }

    private func addresses(_ sections: [HistoryBrowser.Section]) -> [[String]] {
        sections.map { $0.rows.map(\.url.absoluteString) }
    }

    // MARK: Grouping

    @Test func entriesAreGroupedByDayNewestFirst() {
        let store = makeStore()
        visit(store, "https://example.com/old", at: "2026-10-10 09:00")
        visit(store, "https://example.com/yesterday-early", at: "2026-10-11 08:00")
        visit(store, "https://example.com/today", at: "2026-10-12 09:30")
        visit(store, "https://example.com/yesterday-late", at: "2026-10-11 23:59")

        let sections = makeBrowser(store).sections(matching: "")

        #expect(
            addresses(sections) == [
                ["https://example.com/today"],
                ["https://example.com/yesterday-late", "https://example.com/yesterday-early"],
                ["https://example.com/old"],
            ])
        #expect(sections.map(\.day) == ["2026-10-12", "2026-10-11", "2026-10-10"].map { historyTestDate("\($0) 00:00") })
    }

    @Test(arguments: [
        (visited: "2026-10-12 00:00", title: "今天"),
        (visited: "2026-10-11 23:59", title: "昨天"),
        (visited: "2026-10-10 12:00", title: "10月10日 星期六"),
        (visited: "2025-12-31 12:00", title: "2025年12月31日 星期三"),
    ])
    func sectionsAreNamedAfterTheirDay(_ row: (visited: String, title: String)) {
        let store = makeStore()
        visit(store, "https://example.com/a", at: row.visited)

        #expect(makeBrowser(store).sections(matching: "").map(\.title) == [row.title])
    }

    /// 今天 is the store's today: once its clock passes midnight, yesterday's pages are 昨天.
    @Test func theDaysFollowTheStoresNow() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 23:00")
        let browser = makeBrowser(store)
        #expect(browser.sections(matching: "").map(\.title) == ["今天"])

        clock.now = historyTestDate("2026-10-13 00:01")

        #expect(browser.sections(matching: "").map(\.title) == ["昨天"])
    }

    @Test func aRowShowsItsTitleWithTheAddressBelowAndTheTimeVisited() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:05", title: "  Page\n  A ")

        let row = makeBrowser(store).sections(matching: "").first?.rows.first

        #expect(row?.title == "Page A")
        #expect(row?.subtitle == "https://example.com/a")
        #expect(row?.time == "09:05")
    }

    /// No title yet: the address stands in for it, and isn't repeated underneath.
    @Test(arguments: [nil, "   "] as [String?])
    func anUntitledRowShowsItsAddress(_ title: String?) {
        let store = makeStore()
        visit(store, "https://example.com/untitled", at: "2026-10-12 09:00", title: title)

        let row = makeBrowser(store).sections(matching: "").first?.rows.first

        #expect(row?.title == "https://example.com/untitled")
        #expect(row?.subtitle == nil)
    }

    @Test func anEmptyHistoryHasNoSections() {
        #expect(makeBrowser(makeStore()).sections(matching: "").isEmpty)
    }

    // MARK: Search

    @Test(arguments: [
        (query: "", shown: ["https://video.example.com/watch", "https://news.example.org/today"]),
        (query: "   ", shown: ["https://video.example.com/watch", "https://news.example.org/today"]),
        (query: "Cats", shown: ["https://video.example.com/watch"]),
        (query: "cats", shown: ["https://video.example.com/watch"]),
        (query: "news.example", shown: ["https://news.example.org/today"]),
        (query: " news ", shown: ["https://news.example.org/today"]),
        (query: "nothing like it", shown: []),
    ])
    func searchMatchesTitleOrAddress(_ row: (query: String, shown: [String])) {
        let store = makeStore()
        visit(store, "https://news.example.org/today", at: "2026-10-11 09:00", title: "Headlines")
        visit(store, "https://video.example.com/watch", at: "2026-10-12 09:00", title: "Funny Cats")

        let sections = makeBrowser(store).sections(matching: row.query)

        #expect(sections.flatMap(\.rows).map(\.url.absoluteString) == row.shown)
        #expect(sections.allSatisfy { !$0.rows.isEmpty })
    }

    // MARK: Deleting

    @Test func deletingSelectedRowsRemovesThemFromTheStore() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        visit(store, "https://example.com/b", at: "2026-10-12 09:01")
        visit(store, "https://example.com/c", at: "2026-10-11 09:00")
        let browser = makeBrowser(store)

        browser.delete([URL(string: "https://example.com/a")!, URL(string: "https://example.com/c")!])

        #expect(store.entries(since: .distantPast).map(\.url.absoluteString) == ["https://example.com/b"])
        #expect(addresses(browser.sections(matching: "")) == [["https://example.com/b"]])
    }

    @Test func deletingADayRemovesEverythingFromThatDayOnly() {
        let store = makeStore()
        visit(store, "https://example.com/today", at: "2026-10-12 00:00")
        visit(store, "https://example.com/late", at: "2026-10-11 23:59")
        visit(store, "https://example.com/early", at: "2026-10-11 00:00")
        visit(store, "https://example.com/before", at: "2026-10-10 23:59")
        let browser = makeBrowser(store)
        let yesterday = browser.sections(matching: "")[1].day

        browser.deleteDay(yesterday)

        #expect(
            store.entries(since: .distantPast).map(\.url.absoluteString)
                == ["https://example.com/today", "https://example.com/before"])
    }

    /// 删除这一天 means the whole day, including the pages a search is hiding — what the item says.
    @Test func deletingADayWhileSearchingRemovesTheWholeDay() {
        let store = makeStore()
        visit(store, "https://example.com/match", at: "2026-10-11 09:00", title: "match")
        visit(store, "https://example.com/other", at: "2026-10-11 10:00", title: "other")
        let browser = makeBrowser(store)

        browser.deleteDay(browser.sections(matching: "match")[0].day)

        #expect(store.entries(since: .distantPast).isEmpty)
    }

    // MARK: Opening

    @Test func openingHandsTheAddressOn() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        var opened: [URL] = []
        let browser = makeBrowser(store) { opened.append($0) }

        browser.open([URL(string: "https://example.com/a")!], shownIn: browser.sections(matching: ""))

        #expect(opened == [URL(string: "https://example.com/a")!])
    }

    /// There is one widget, so a double-click on a multiple selection opens one page: the topmost.
    @Test func openingSeveralOpensTheTopmost() {
        let store = makeStore()
        visit(store, "https://example.com/older", at: "2026-10-11 09:00")
        visit(store, "https://example.com/newer", at: "2026-10-12 09:00")
        visit(store, "https://example.com/newest", at: "2026-10-12 09:30")
        var opened: [URL] = []
        let browser = makeBrowser(store) { opened.append($0) }

        browser.open(
            [URL(string: "https://example.com/older")!, URL(string: "https://example.com/newer")!],
            shownIn: browser.sections(matching: ""))

        #expect(opened == [URL(string: "https://example.com/newer")!])
    }

    @Test func openingNothingOpensNothing() {
        let store = makeStore()
        visit(store, "https://example.com/a", at: "2026-10-12 09:00")
        var opened: [URL] = []
        let browser = makeBrowser(store) { opened.append($0) }

        browser.open([], shownIn: browser.sections(matching: ""))
        browser.open([URL(string: "https://example.com/gone")!], shownIn: browser.sections(matching: ""))

        #expect(opened.isEmpty)
    }
}
