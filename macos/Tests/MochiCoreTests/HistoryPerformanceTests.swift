import Foundation
import Testing

@testable import MochiCore

/// How the 历史记录 window holds up under a heavy year of history (#116, #118): 300 000 visits,
/// about 800 a day. Timing-sensitive, so off by default — CI's machines are too uneven to hold a
/// millisecond budget. Run with `MOCHI_HISTORY_BENCH=1 swift test --filter HistoryPerformanceTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MOCHI_HISTORY_BENCH"] != nil), .serialized)
struct HistoryPerformanceTests {
    private static let visits = 300_000
    private static let budget = Duration.milliseconds(100)

    private static func heavyHistory() -> (HistoryStore, HistoryBrowser) {
        let clock = TestClock(historyTestDate("2026-10-12 10:00"))
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        let start = historyTestDate("2025-10-13 00:00")
        let step = clock.now.timeIntervalSince(start) / Double(visits)
        let icon = Data("an icon".utf8)
        for index in 0..<visits {
            clock.now = start.addingTimeInterval(Double(index) * step)
            let id = store.recordVisit(to: URL(string: "https://site\(index % 500).example.com/page/\(index)")!)!
            store.updateTitle("Page \(index) of site \(index % 500)", ofVisit: id)
            if index % 3 == 0 { store.updateFavicon(icon, ofVisit: id) }
        }
        clock.now = historyTestDate("2026-10-12 10:00")
        return (store, HistoryBrowser(store: store, open: { _ in }))
    }

    private static func time(_ work: () -> Void) -> Duration {
        let clock = ContinuousClock()
        return clock.measure(work)
    }

    @Test func openingAndUnfoldingADayStayWithinBudget() {
        let (_, browser) = Self.heavyHistory()

        let opening = Self.time { browser.resetExpansion() }
        let unfolding = Self.time { browser.setExpanded(true, day: browser.days[100].day) }

        print("history bench: open \(opening), unfold \(unfolding), days \(browser.days.count)")
        #expect(browser.days.count >= 365)
        #expect(browser.days[100].rows.count == browser.days[100].visits)
        #expect(opening < Self.budget)
        #expect(unfolding < Self.budget)
    }

    /// A search reads every visit, but a narrow one returns few: the budget is the scan.
    @Test func searchingStaysWithinBudget() {
        let (_, browser) = Self.heavyHistory()
        browser.resetExpansion()

        let keywords = Self.time { browser.search("site42.example.com/page/1") }
        let keywordMatches = browser.matchCount
        let site = Self.time { browser.search("site:site42.example.com Page 3") }

        print("history bench: search \(keywords) (\(keywordMatches)), site: \(site) (\(browser.matchCount))")
        #expect(keywordMatches > 0)
        #expect(browser.matchCount > 0)
        #expect(keywords < Self.budget)
        #expect(site < Self.budget)
    }

    /// The address bar asks on every keystroke (#122): a first letter that is in nearly every
    /// address is the worst case, a narrower word the usual one.
    @Test func addressBarCandidatesStayWithinBudget() {
        let (store, _) = Self.heavyHistory()

        let since = store.now().addingTimeInterval(-HistoryStore.suggestionWindow)
        let broad = Self.time { _ = store.suggestionCandidates(matching: ["s"], since: since) }
        let narrow = Self.time { _ = store.suggestionCandidates(matching: ["site42"], since: since) }

        print("history bench: address bar broad \(broad), narrow \(narrow)")
        #expect(broad < Self.budget)
        #expect(narrow < Self.budget)
    }
}
