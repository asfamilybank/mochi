import Foundation
import Testing

@testable import MochiCore

/// The address bar's history candidates (#122, ADR-0034): computed from the visits every time,
/// so whatever deletes visits takes their suggestions with them.
@Suite struct HistorySuggestionCandidatesTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    private func makeStore() -> HistoryStore {
        let clock = clock
        return HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
    }

    private func visit(_ store: HistoryStore, _ url: String, title: String? = nil, at date: String) {
        clock.now = historyTestDate(date)
        let id = store.recordVisit(to: URL(string: url)!)!
        if let title { store.updateTitle(title, ofVisit: id) }
    }

    private func addresses(_ candidates: [AddressSuggestionCandidate]) -> [String] {
        candidates.map(\.url.absoluteString)
    }

    @Test func anAddressVisitedManyTimesIsOneCandidateWithItsLatestTitleAndVisit() {
        let store = makeStore()
        visit(store, "https://github.com/", title: "Old", at: "2026-10-10 09:00")
        visit(store, "https://github.com/", title: "GitHub", at: "2026-10-12 09:00")
        clock.now = historyTestDate("2026-10-12 10:00")

        let candidates = store.suggestionCandidates(matching: ["git"], since: nil)

        #expect(addresses(candidates) == ["https://github.com/"])
        #expect(candidates.first?.title == "GitHub")
        #expect(candidates.first?.lastVisitedAt == historyTestDate("2026-10-12 09:00"))
    }

    /// The latest visit may not have its title yet — the page that is still loading.
    @Test func aLatestVisitWithNoTitleYetKeepsTheTitleBefore() {
        let store = makeStore()
        visit(store, "https://github.com/", title: "GitHub", at: "2026-10-11 09:00")
        visit(store, "https://github.com/", at: "2026-10-12 09:00")

        #expect(store.suggestionCandidates(matching: ["git"], since: nil).first?.title == "GitHub")
    }

    /// Recent visits weigh more than old ones: four visits a year ago count for less than one
    /// yesterday.
    @Test func recentVisitsWeighMore() throws {
        let store = makeStore()
        for day in 1...4 {
            visit(store, "https://old.example.com/", at: "2025-11-0\(day) 09:00")
        }
        visit(store, "https://new.example.com/", at: "2026-10-11 09:00")
        clock.now = historyTestDate("2026-10-12 10:00")

        let candidates = store.suggestionCandidates(matching: ["example"], since: nil)

        let old = try #require(candidates.first { $0.url.host == "old.example.com" })
        let new = try #require(candidates.first { $0.url.host == "new.example.com" })
        #expect(new.frecency > old.frecency)
    }

    @Test func moreVisitsWeighMore() throws {
        let store = makeStore()
        visit(store, "https://a.example.com/", at: "2026-10-11 09:00")
        visit(store, "https://b.example.com/", at: "2026-10-11 09:00")
        visit(store, "https://b.example.com/", at: "2026-10-11 10:00")
        clock.now = historyTestDate("2026-10-12 10:00")

        let candidates = store.suggestionCandidates(matching: ["example"], since: nil)

        #expect(addresses(candidates) == ["https://b.example.com/", "https://a.example.com/"])
    }

    /// The store narrows by every word appearing somewhere in the address or a title; the exact
    /// word-start rule is the session's.
    @Test(arguments: [
        (words: ["git"], found: ["https://github.com/"]),
        (words: ["hub"], found: ["https://github.com/"]),
        (words: ["代码"], found: ["https://github.com/"]),
        (words: ["git", "代码"], found: ["https://github.com/"]),
        (words: ["git", "swift"], found: []),
        (words: ["100%"], found: []),
        (words: ["a_b"], found: []),
    ] as [(words: [String], found: [String])])
    func everyWordMustAppearInTheAddressOrATitle(_ row: (words: [String], found: [String])) {
        let store = makeStore()
        visit(store, "https://github.com/", title: "GitHub 代码托管", at: "2026-10-12 09:00")
        visit(store, "https://axb.example.com/", title: "100 percent", at: "2026-10-12 09:00")

        #expect(addresses(store.suggestionCandidates(matching: row.words, since: nil)) == row.found)
    }

    @Test func visitsBeforeTheRetentionLimitDoNotCount() {
        let store = makeStore()
        visit(store, "https://old.example.com/", at: "2025-01-01 09:00")
        visit(store, "https://new.example.com/", at: "2026-10-11 09:00")

        let candidates = store.suggestionCandidates(matching: ["example"], since: historyTestDate("2026-01-01 00:00"))

        #expect(addresses(candidates) == ["https://new.example.com/"])
    }

    @Test func deletedVisitsAreNoLongerSuggested() {
        let store = makeStore()
        visit(store, "https://github.com/", at: "2026-10-12 09:00")

        store.removeVisits(since: .distantPast)

        #expect(store.suggestionCandidates(matching: ["git"], since: nil).isEmpty)
    }

    @Test func atMostTheLimitAreReturnedTheMostFrecentFirst() {
        let store = makeStore()
        for index in 0..<5 {
            for _ in 0...index { visit(store, "https://s\(index).example.com/", at: "2026-10-12 09:00") }
        }

        let candidates = store.suggestionCandidates(matching: ["example"], since: nil, limit: 2)

        #expect(addresses(candidates) == ["https://s4.example.com/", "https://s3.example.com/"])
    }

    @Test func theLatestVisitsIconComesAlong() {
        let store = makeStore()
        let icon = Data([0x89, 0x50, 0x4E, 0x47])
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: URL(string: "https://github.com/")!, favicon: icon)

        let candidate = store.suggestionCandidates(matching: ["git"], since: nil).first

        #expect(candidate?.faviconID.flatMap(store.favicon) == icon)
    }
}
