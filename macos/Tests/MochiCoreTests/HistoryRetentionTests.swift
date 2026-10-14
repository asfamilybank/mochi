import Foundation
import Testing

@testable import MochiCore

/// 移除历史记录项目 (#110): where each retention period cuts off, counted back from "now" in the
/// injected calendar, and the store dropping what lies before it.
@Suite struct HistoryRetentionTests {
    private let now = historyTestDate("2026-10-12 10:00")

    @Test(arguments: [
        (retention: HistoryRetention.oneDay, cutoff: "2026-10-11 10:00"),
        (retention: .oneWeek, cutoff: "2026-10-05 10:00"),
        (retention: .twoWeeks, cutoff: "2026-09-28 10:00"),
        (retention: .oneMonth, cutoff: "2026-09-12 10:00"),
        (retention: .oneYear, cutoff: "2025-10-12 10:00"),
    ])
    func eachPeriodCutsOffThatLongBeforeNow(_ row: (retention: HistoryRetention, cutoff: String)) {
        #expect(row.retention.cutoff(now: now, calendar: historyTestCalendar) == historyTestDate(row.cutoff))
    }

    /// A month is a calendar month, not 30 days: from 31 March it reaches back to the last day of
    /// February.
    @Test func aMonthIsACalendarMonth() {
        let cutoff = HistoryRetention.oneMonth.cutoff(now: historyTestDate("2026-03-31 10:00"), calendar: historyTestCalendar)
        #expect(cutoff == historyTestDate("2026-02-28 10:00"))
    }

    @Test func manualHasNoCutoff() {
        #expect(HistoryRetention.manual.cutoff(now: now, calendar: historyTestCalendar) == nil)
    }

    @Test func thePeriodsAreOfferedShortestFirstAndDefaultToOneYear() {
        #expect(HistoryRetention.allCases == [.oneDay, .oneWeek, .twoWeeks, .oneMonth, .oneYear, .manual])
        #expect(HistoryRetention.defaultRetention == .oneYear)
        #expect(HistoryRetention.allCases.map(\.displayName) == ["一天后", "一周后", "两周后", "一个月后", "一年后", "手动"])
    }

    // MARK: The store

    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    /// One page visited 25 hours ago, one exactly a day ago, one an hour ago.
    private func storeWithThreeVisits() -> HistoryStore {
        let clock = clock
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        clock.now = historyTestDate("2026-10-11 09:00")
        store.recordVisit(to: URL(string: "https://example.com/old")!)
        clock.now = historyTestDate("2026-10-11 10:00")
        store.recordVisit(to: URL(string: "https://example.com/edge")!)
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: URL(string: "https://example.com/new")!)
        clock.now = historyTestDate("2026-10-12 10:00")
        return store
    }

    @Test func theStoreRemovesWhatWasVisitedBeforeTheCutoffAtItsOwnNow() {
        let store = storeWithThreeVisits()

        store.removeVisits(olderThan: .oneDay)

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/new", "/edge"])
    }

    @Test func manualRemovesNothing() {
        let store = storeWithThreeVisits()

        store.removeVisits(olderThan: .manual)

        #expect(store.visits(since: .distantPast).count == 3)
    }
}
