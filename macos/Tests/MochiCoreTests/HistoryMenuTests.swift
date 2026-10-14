import Foundation
import Testing

@testable import MochiCore

@Suite struct HistoryMenuTests {
    private let now = historyTestDate("2026-10-12 10:00")

    /// `count` visits on the day of `day`, one a minute from 08:00, newest first like the store
    /// returns them.
    private func entries(_ count: Int, on day: String, prefix: String = "p") -> [HistoryVisit] {
        (0..<count).reversed().map { minute in
            HistoryVisit(
                id: Int64(minute), url: URL(string: "https://example.com/\(prefix)\(minute)")!,
                title: "\(prefix)\(minute)",
                visitedAt: historyTestDate("\(day) 08:00").addingTimeInterval(Double(minute) * 60))
        }
    }

    private func visit(_ url: String, title: String?, at time: Date) -> HistoryVisit {
        HistoryVisit(id: 1, url: URL(string: url)!, title: title, visitedAt: time)
    }

    private func build(_ visits: [HistoryVisit]) -> HistoryMenu {
        HistoryMenu.build(visits: visits, now: now, calendar: historyTestCalendar)
    }

    @Test(arguments: [
        (count: 0, shown: 0),
        (count: 1, shown: 1),
        (count: 15, shown: 15),
        (count: 16, shown: 15),
        (count: 40, shown: 15),
    ])
    func todayListsTheFifteenMostRecent(_ row: (count: Int, shown: Int)) {
        let menu = build(entries(row.count, on: "2026-10-12"))

        #expect(menu.today.count == row.shown)
        if row.count > 0 { #expect(menu.today.first?.title == "p\(row.count - 1)") }
        #expect(menu.earlierDays.isEmpty)
    }

    @Test(arguments: [
        (count: 1, shown: 1),
        (count: 30, shown: 30),
        (count: 31, shown: 30),
        (count: 100, shown: 30),
    ])
    func eachEarlierDayListsAtMostThirty(_ row: (count: Int, shown: Int)) {
        let menu = build(entries(row.count, on: "2026-10-10"))

        #expect(menu.earlierDays.map(\.items.count) == [row.shown])
        #expect(menu.earlierDays.first?.items.first?.title == "p\(row.count - 1)")
    }

    /// Only days with something in them, newest first, and never more than six days back.
    @Test func onlyThePastSixDaysThatHaveEntriesGetASubmenu() {
        let menu = build(
            entries(1, on: "2026-10-11", prefix: "yesterday") + entries(2, on: "2026-10-08", prefix: "thursday")
                + entries(1, on: "2026-10-06", prefix: "sixDaysAgo") + entries(1, on: "2026-10-05", prefix: "tooOld"))

        #expect(
            menu.earlierDays.map(\.day) == [
                historyTestDate("2026-10-11 00:00"), historyTestDate("2026-10-08 00:00"),
                historyTestDate("2026-10-06 00:00"),
            ])
        #expect(menu.earlierDays.map(\.items.count) == [1, 2, 1])
    }

    @Test func midnightSeparatesTodayFromYesterday() {
        let justBefore = visit("https://example.com/before", title: "before", at: historyTestDate("2026-10-11 23:59"))
        let justAfter = visit("https://example.com/after", title: "after", at: historyTestDate("2026-10-12 00:00"))

        let menu = build([justAfter, justBefore])

        #expect(menu.today.map(\.title) == ["after"])
        #expect(menu.earlierDays.map { $0.items.map(\.title) } == [["before"]])
    }

    /// Visit by visit, like the window (#114): a page visited twice today is listed twice.
    @Test func aPageVisitedTwiceIsListedTwice() {
        let menu = build([
            visit("https://example.com/a", title: "A", at: now),
            visit("https://example.com/b", title: "B", at: now.addingTimeInterval(-60)),
            visit("https://example.com/a", title: "A", at: now.addingTimeInterval(-120)),
        ])

        #expect(menu.today.map(\.title) == ["A", "B", "A"])
    }

    /// The oldest moment the menu shows, for fetching just enough from the store.
    @Test func theMenuReachesBackToTheStartOfSixDaysAgo() {
        #expect(HistoryMenu.earliestDay(now: now, calendar: historyTestCalendar) == historyTestDate("2026-10-06 00:00"))
    }

    @Test func aSubmenuIsNamedAfterItsDate() {
        let menu = build(entries(1, on: "2026-10-11"))

        #expect(menu.earlierDays.first?.title == "10月11日 星期日")
    }

    @Test(arguments: [
        (title: "A page", url: "https://example.com/a", shown: "A page"),
        (title: nil, url: "https://example.com/a", shown: "https://example.com/a"),
        (title: "   ", url: "https://example.com/a", shown: "https://example.com/a"),
        (title: "Line\none", url: "https://example.com/a", shown: "Line one"),
    ] as [(title: String?, url: String, shown: String)])
    func anItemShowsTheTitleOrElseTheAddress(_ row: (title: String?, url: String, shown: String)) {
        let entry = visit(row.url, title: row.title, at: now)

        #expect(build([entry]).today == [HistoryMenu.Item(title: row.shown, url: URL(string: row.url)!)])
    }

    /// ⌘Y (显示全部历史记录) belongs to the History menu, so no global hotkey or mapping may take it.
    @Test func showAllHistoryIsAReservedMenuShortcut() {
        let showAllHistory = Hotkey(keyCode: 0x10, modifierFlags: 0x0100)
        #expect(DefaultHotkeys.showAllHistory == showAllHistory)
        #expect(HotkeyDisplay.describe(showAllHistory) == "⌘Y")
        #expect(DefaultHotkeys.reservedLocalMenuShortcuts.contains(showAllHistory))
    }

    @Test func aLongTitleIsCutShort() {
        let entry = visit("https://example.com/a", title: String(repeating: "长", count: 200), at: now)

        let shown = build([entry]).today.first?.title ?? ""

        #expect(shown.count == HistoryMenu.maximumTitleLength)
        #expect(shown.hasSuffix("…"))
    }
}
