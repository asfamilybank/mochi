import Foundation
import Testing

@testable import MochiCore

/// 书签 (#121, ADR-0033): ⌘D adds the page and offers its name for editing, the 书签 menu opens a
/// bookmark the way history does, and a bookmark's icon follows the site's.
@Suite struct OrchestratorBookmarkTests {
    private let iconA = Data([0x89, 0x50, 0x4E, 0x47, 0xA])
    private let iconB = Data([0x89, 0x50, 0x4E, 0x47, 0xB])
    private let page = URL(string: "https://github.com/asfamilybank/mochi")!

    private func makeOrchestrator(
        config: WidgetConfig = WidgetConfig(url: URL(string: "https://start.example.com")!),
        historyStore: HistoryStore? = nil
    ) -> (FakePlatformOps, Orchestrator, BookmarkStore) {
        let fake = FakePlatformOps()
        let bookmarks = BookmarkStore(databaseURL: nil)
        let orchestrator = Orchestrator(
            platformOps: fake, currentConfig: { config }, historyStore: historyStore, bookmarkStore: bookmarks)
        orchestrator.start()
        return (fake, orchestrator, bookmarks)
    }

    /// The page as the platform reports it: its address, then its title.
    private func show(_ url: URL, title: String?, on fake: FakePlatformOps) {
        fake.simulateMainFrameURLChanged(url)
        fake.simulatePageTitleChanged(title)
    }

    // MARK: ⌘D

    @Test func addingBookmarksThePageUnderItsTitleAndOffersTheNameForEditing() {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "asfamilybank/mochi", on: fake)

        orchestrator.perform(.addBookmark)

        #expect(bookmarks.all().map(\.name) == ["asfamilybank/mochi"])
        #expect(bookmarks.all().map(\.url) == [page])
        #expect(fake.bookmarkEditors.map(\.name) == ["asfamilybank/mochi"])
        // 移除 is offered only on a page that already was a bookmark (#121).
        #expect(fake.bookmarkEditors.map(\.offersRemove) == [false])
    }

    /// A page with no title yet is bookmarked under its address.
    @Test func aPageWithNoTitleIsBookmarkedUnderItsAddress() {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "  ", on: fake)

        orchestrator.perform(.addBookmark)

        #expect(bookmarks.all().map(\.name) == [page.absoluteString])
    }

    @Test func theBookmarkTakesTheSitesIcon() {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateSiteIconLoaded(iconA, for: page)

        orchestrator.perform(.addBookmark)

        #expect(bookmarks.all().first?.faviconID.flatMap(bookmarks.favicon) == iconA)
    }

    /// An icon fetched for another site isn't this page's.
    @Test func anotherSitesIconIsNotTaken() {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateMainFrameURLChanged(URL(string: "https://other.example.com/")!)
        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://other.example.com/")!)
        show(page, title: "Mochi", on: fake)

        orchestrator.perform(.addBookmark)

        #expect(bookmarks.all().first?.faviconID == nil)
    }

    /// ⌘D on a page that is already a bookmark adds nothing: it only opens the editor, under the
    /// bookmark's own name.
    @Test func onAnAlreadyBookmarkedPageItOnlyOpensTheEditor() throws {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "我的仓库", url: page).get()
        show(page, title: "asfamilybank/mochi", on: fake)

        #expect(orchestrator.isCurrentPageBookmarked)
        orchestrator.perform(.addBookmark)

        #expect(bookmarks.all().map(\.name) == ["我的仓库"])
        #expect(fake.bookmarkEditors.map(\.name) == ["我的仓库"])
        #expect(fake.bookmarkEditors.map(\.offersRemove) == [true])
    }

    @Test(arguments: [
        (answer: BookmarkEditorAnswer.done(name: "Mochi 仓库"), names: ["Mochi 仓库"]),
        (answer: BookmarkEditorAnswer.done(name: "  "), names: ["asfamilybank/mochi"]),
        (answer: BookmarkEditorAnswer.cancel, names: ["asfamilybank/mochi"]),
        (answer: BookmarkEditorAnswer.remove, names: []),
    ])
    func theEditorsAnswerIsKept(_ row: (answer: BookmarkEditorAnswer, names: [String])) {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "asfamilybank/mochi", on: fake)
        orchestrator.perform(.addBookmark)

        fake.simulateBookmarkEditorAnswered(row.answer)

        #expect(bookmarks.all().map(\.name) == row.names)
    }

    // MARK: When it is offered

    @Test func itIsOfferedOnAWebPage() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)

        #expect(orchestrator.canPerform(.addBookmark))
    }

    /// Ghost Mode takes nothing that needs the user (ADR-0012), and the editor does.
    @Test func itIsNotOfferedInGhostMode() {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(!orchestrator.canPerform(.addBookmark))
        orchestrator.perform(.addBookmark)
        #expect(bookmarks.all().isEmpty)
        #expect(fake.bookmarkEditors.isEmpty)
    }

    /// Float Mode has no address bar for the editor to hang from (#147, ADR-0035).
    @Test func itIsNotOfferedInFloatMode() {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleFloatMode)

        #expect(!orchestrator.canPerform(.addBookmark))
        orchestrator.perform(.addBookmark)
        #expect(bookmarks.all().isEmpty)
        #expect(fake.bookmarkEditors.isEmpty)
    }

    @Test func itIsNotOfferedOnTheEmptyPage() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateEmptyPageVisibilityChanged(true)

        #expect(!orchestrator.canPerform(.addBookmark))
    }

    @Test(arguments: ["about:blank", "data:text/html,<p>hi</p>", "file:///Users/someone/page.html"])
    func itIsNotOfferedOffTheWeb(_ address: String) {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(URL(string: address)!, title: "Local", on: fake)

        #expect(!orchestrator.canPerform(.addBookmark))
    }

    @Test func itIsNotOfferedWithoutAWidget() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateWindowWillClose()

        #expect(!orchestrator.canPerform(.addBookmark))
    }

    /// A reopened widget starts with no page known — nothing left over from the one before.
    @Test func aReopenedWidgetForgetsThePageBefore() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateWindowWillClose()

        orchestrator.openWidget()

        #expect(!orchestrator.canPerform(.addBookmark))
    }

    // MARK: The menu

    @Test func theMenuListsTheBookmarksAndTheirIcons() throws {
        let (_, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "A", url: URL(string: "https://a.example.com/")!, favicon: iconA).get()
        try bookmarks.add(name: "B", url: URL(string: "https://b.example.com/")!).get()

        let items = orchestrator.bookmarkMenu().items

        #expect(items.map(\.title) == ["A", "B"])
        #expect(items.map { $0.faviconID.flatMap(orchestrator.bookmarkFavicon) } == [iconA, nil])
    }

    @Test func withoutAStoreThereAreNoBookmarksAndNothingIsOffered() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig() })
        orchestrator.start()
        show(page, title: "Mochi", on: fake)

        #expect(orchestrator.bookmarkMenu().items.isEmpty)
        #expect(!orchestrator.canPerform(.addBookmark))
    }

    // MARK: Opening a bookmark

    @Test func openingABookmarkLoadsItInTheWidget() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }

        orchestrator.openBookmark(page)

        #expect(fake.loadedURLs.last?.url == page)
    }

    /// Like history (`CONTEXT.md`): an explicit choice, followed without leaving Ghost Mode.
    @Test func openingABookmarkInGhostModeStaysInGhostMode() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        let passthroughChanges = fake.mousePassthroughChanges.count

        orchestrator.openBookmark(page)

        #expect(fake.loadedURLs.last?.url == page)
        #expect(fake.mousePassthroughChanges.count == passthroughChanges)
    }

    /// A closed widget reopens straight at the bookmark — the startup page is never loaded first.
    @Test func openingABookmarkReopensAClosedWidgetAtIt() {
        let (fake, orchestrator, _) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        fake.simulateWindowWillClose()
        let loadsBefore = fake.loadedURLs.count

        orchestrator.openBookmark(page)

        #expect(fake.loadedURLs.dropFirst(loadsBefore).map(\.url) == [page])
        #expect(fake.loadedURLs.last?.windowID == 2)
    }

    // MARK: The 书签 window (#123)

    @Test func theWindowOpensABookmarkTheWayTheMenuDoes() throws {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        let bookmark = try bookmarks.add(name: "Mochi", url: page).get()
        fake.simulateWindowWillClose()
        let browser = try #require(orchestrator.makeBookmarkBrowser())
        browser.reload()

        browser.open([bookmark.id])

        #expect(fake.loadedURLs.last.map { [$0.url.absoluteString, "\($0.windowID)"] } == [page.absoluteString, "2"])
    }

    /// The menu is rebuilt from the same store, so it follows what the window changes.
    @Test func theMenuFollowsWhatTheWindowChanges() throws {
        let (_, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        let bookmark = try bookmarks.add(name: "Mochi", url: page).get()
        let browser = try #require(orchestrator.makeBookmarkBrowser())
        browser.reload()

        _ = browser.edit(bookmark.id, name: "麻糬", address: page.absoluteString)

        #expect(orchestrator.bookmarkMenu().items.map(\.title) == ["麻糬"])
    }

    @Test func withoutAStoreThereIsNoWindow() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig() })

        #expect(orchestrator.makeBookmarkBrowser() == nil)
    }

    // MARK: Icons follow the site

    @Test func visitingABookmarkUpdatesAChangedIcon() throws {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "Mochi", url: page, favicon: iconA).get()
        show(page, title: "Mochi", on: fake)

        fake.simulateSiteIconLoaded(iconB, for: page)

        #expect(bookmarks.all().first?.faviconID.flatMap(bookmarks.favicon) == iconB)
    }

    /// A bookmark added with no icon (in the 书签 window) gets one on its first visit.
    @Test func aBookmarkWithNoIconGetsOneOnItsFirstVisit() throws {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "Mochi", url: page).get()
        show(page, title: "Mochi", on: fake)

        fake.simulateSiteIconLoaded(iconA, for: page)

        #expect(bookmarks.all().first?.faviconID.flatMap(bookmarks.favicon) == iconA)
    }

    /// Moving within the site loads no new icon; the one the site already has is the bookmark's.
    @Test func aBookmarkReachedWithinTheSiteTakesTheSitesIcon() throws {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "Mochi", url: page).get()
        show(URL(string: "https://github.com/")!, title: "GitHub", on: fake)
        fake.simulateSiteIconLoaded(iconA, for: URL(string: "https://github.com/")!)

        fake.simulateMainFrameURLChanged(page)

        #expect(bookmarks.all().first?.faviconID.flatMap(bookmarks.favicon) == iconA)
    }

    @Test func anotherPagesIconIsNotTheBookmarks() throws {
        let (fake, orchestrator, bookmarks) = makeOrchestrator()
        defer { withExtendedLifetime(orchestrator) {} }
        try bookmarks.add(name: "Mochi", url: page, favicon: iconA).get()
        show(URL(string: "https://github.com/explore")!, title: "Explore", on: fake)

        fake.simulateSiteIconLoaded(iconB, for: URL(string: "https://github.com/explore")!)

        #expect(bookmarks.all().first?.faviconID.flatMap(bookmarks.favicon) == iconA)
    }

    // MARK: Clearing leaves bookmarks alone

    /// No clearing reaches bookmarks (ADR-0033): every kind of 清除浏览数据 over all time,
    /// 清除历史记录 from the history window, and 移除所有网站数据.
    @Test func clearingLeavesBookmarksAndTheirIcons() throws {
        let history = HistoryStore(databaseURL: nil)
        let (fake, orchestrator, bookmarks) = makeOrchestrator(historyStore: history)
        defer { withExtendedLifetime(orchestrator) {} }
        show(page, title: "Mochi", on: fake)
        fake.simulateSiteIconLoaded(iconA, for: page)
        orchestrator.perform(.addBookmark)
        let settings = SettingsController(
            platformOps: fake, currentConfig: { WidgetConfig() }, persist: { _ in }, historyStore: history)

        settings.clearBrowsingData(Set(BrowsingDataKind.allCases), from: .allTime)
        try #require(orchestrator.makeHistoryBrowser()).clearHistory(from: .allTime)
        settings.removeDataOfAllWebsites {}

        #expect(bookmarks.all().map(\.name) == ["Mochi"])
        #expect(bookmarks.all().first?.faviconID.flatMap(bookmarks.favicon) == iconA)
    }
}
