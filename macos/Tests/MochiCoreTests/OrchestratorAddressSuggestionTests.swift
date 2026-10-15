import Foundation
import Testing

@testable import MochiCore

/// 地址栏建议 (#122, ADR-0034): each widget's address bar is given where its suggestions come
/// from — the history, read at the moment of typing.
@Suite struct OrchestratorAddressSuggestionTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    private func makeOrchestrator(
        config: @escaping () -> WidgetConfig = { WidgetConfig(url: URL(string: "https://start.example.com")!) }
    ) -> (FakePlatformOps, Orchestrator, HistoryStore) {
        let fake = FakePlatformOps()
        let clock = clock
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: config, historyStore: store)
        orchestrator.start()
        return (fake, orchestrator, store)
    }

    private func visit(_ store: HistoryStore, _ url: String, title: String? = nil, at date: String) {
        clock.now = historyTestDate(date)
        let id = store.recordVisit(to: URL(string: url)!)!
        if let title { store.updateTitle(title, ofVisit: id) }
    }

    private func suggested(_ fake: FakePlatformOps, _ words: [String], windowID: Int = 1) -> [String] {
        (fake.addressSuggestionSources[windowID]?.candidates(words) ?? []).map(\.url.absoluteString)
    }

    @Test func theAddressBarIsGivenTheHistorysCandidates() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://github.com/", title: "GitHub", at: "2026-10-12 09:00")

        #expect(suggested(fake, ["git"]) == ["https://github.com/"])
    }

    @Test func theCandidatesIconsAreTheHistorys() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        let icon = Data([0x89, 0x50, 0x4E, 0x47])
        store.recordVisit(to: URL(string: "https://github.com/")!, favicon: icon)

        let candidate = fake.addressSuggestionSources[1]?.candidates(["git"]).first

        #expect(candidate?.faviconID.flatMap { fake.addressSuggestionSources[1]?.favicon($0) } == icon)
    }

    /// The source reads the history when asked, not when the widget opened.
    @Test func visitsMadeAfterTheWidgetOpenedAreSuggested() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        visit(store, "https://github.com/", at: "2026-10-12 09:00")

        #expect(suggested(fake, ["git"]) == ["https://github.com/"])
    }

    /// Visits the retention setting has expired, but nobody has removed yet, aren't suggested.
    @Test func expiredVisitsAreNotSuggested() {
        var config = WidgetConfig(url: URL(string: "https://start.example.com")!)
        let (fake, orchestrator, store) = makeOrchestrator(config: { config })
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://old.example.com/", at: "2026-10-01 09:00")
        visit(store, "https://new.example.com/", at: "2026-10-12 09:00")

        config.historyRetention = .oneWeek

        #expect(suggested(fake, ["example"]) == ["https://new.example.com/"])
    }

    /// Only the last 90 days count, whatever the retention (`HistoryStore.suggestionWindow`).
    @Test func onlyTheLastNinetyDaysAreSuggested() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://old.example.com/", at: "2026-06-01 09:00")
        visit(store, "https://new.example.com/", at: "2026-10-12 09:00")

        #expect(suggested(fake, ["example"]) == ["https://new.example.com/"])
    }

    @Test func clearedHistoryIsNoLongerSuggested() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://github.com/", at: "2026-10-12 09:00")

        store.removeVisits(since: .distantPast)

        #expect(suggested(fake, ["git"]).isEmpty)
    }

    @Test func aReopenedWidgetIsGivenTheSourceToo() {
        let (fake, orchestrator, store) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://github.com/", at: "2026-10-12 09:00")
        fake.simulateWindowWillClose()

        orchestrator.openWidget()

        #expect(suggested(fake, ["git"], windowID: 2) == ["https://github.com/"])
    }

    @Test func withoutAHistoryThereIsNothingToSuggest() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig() })
        orchestrator.start()
        defer { withExtendedLifetime(orchestrator) {} }

        #expect(suggested(fake, ["git"]).isEmpty)
    }

    // MARK: Bookmarks (#125)

    private func makeOrchestratorWithBookmarks() -> (FakePlatformOps, Orchestrator, HistoryStore, BookmarkStore) {
        let fake = FakePlatformOps()
        let clock = clock
        let store = HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
        let bookmarks = BookmarkStore(databaseURL: nil)
        let orchestrator = Orchestrator(
            platformOps: fake, currentConfig: { WidgetConfig(url: URL(string: "https://start.example.com")!) },
            historyStore: store, bookmarkStore: bookmarks)
        orchestrator.start()
        return (fake, orchestrator, store, bookmarks)
    }

    @Test func theBookmarksAreGivenInTheirOrderReadWhenAsked() throws {
        let (fake, orchestrator, _, bookmarks) = makeOrchestratorWithBookmarks()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "B", url: URL(string: "https://b.example.com/")!).get()
        try bookmarks.add(name: "A", url: URL(string: "https://a.example.com/")!).get()

        let given = fake.addressSuggestionSources[1]?.bookmarks() ?? []

        #expect(given.map(\.bookmarkName) == ["B", "A"])
        #expect(given.map(\.url.absoluteString) == ["https://b.example.com/", "https://a.example.com/"])
    }

    /// A bookmarked page that was visited is one candidate: the history's counts, the bookmark's
    /// name. A bookmark never visited is a candidate too.
    @Test func bookmarksAndHistoryAreOneCandidatePerAddress() throws {
        let (fake, orchestrator, store, bookmarks) = makeOrchestratorWithBookmarks()
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://github.com/", title: "GitHub", at: "2026-10-12 09:00")
        try bookmarks.add(name: "代码", url: URL(string: "https://github.com/")!).get()
        try bookmarks.add(name: "Gitea", url: URL(string: "https://gitea.example.com/")!).get()

        let candidates = fake.addressSuggestionSources[1]?.candidates(["git"]) ?? []

        #expect(candidates.map(\.url.absoluteString).sorted() == ["https://gitea.example.com/", "https://github.com/"])
        let github = try #require(candidates.first { $0.url.host == "github.com" })
        #expect(github.bookmarkName == "代码")
        #expect(github.title == "GitHub")
        #expect(github.frecency > 0)
    }

    @Test func aBookmarksIconIsFoundToo() throws {
        let (fake, orchestrator, _, bookmarks) = makeOrchestratorWithBookmarks()
        defer { withExtendedLifetime(orchestrator) {} }
        let icon = Data([0x89, 0x50, 0x4E, 0x47, 0x1])
        try bookmarks.add(name: "A", url: URL(string: "https://a.example.com/")!, favicon: icon).get()

        let source = try #require(fake.addressSuggestionSources[1])
        let id = try #require(source.bookmarks().first?.faviconID)

        #expect(source.favicon(id) == icon)
    }

    /// A bookmark found by its name alone — not by its address or any title — still ranks by how
    /// often it was visited.
    @Test func aBookmarkFoundByItsNameKeepsItsVisits() throws {
        let (fake, orchestrator, store, bookmarks) = makeOrchestratorWithBookmarks()
        defer { withExtendedLifetime(orchestrator) {} }
        visit(store, "https://github.com/", title: "GitHub", at: "2026-10-12 08:00")
        visit(store, "https://github.com/", title: "GitHub", at: "2026-10-12 09:00")
        try bookmarks.add(name: "工作", url: URL(string: "https://github.com/")!).get()

        let candidates = fake.addressSuggestionSources[1]?.candidates(["工作"]) ?? []

        let github = try #require(candidates.first { $0.url.host == "github.com" })
        #expect(github.frecency == 200)
        #expect(github.title == "GitHub")
        #expect(github.lastVisitedAt == historyTestDate("2026-10-12 09:00"))
    }
}
