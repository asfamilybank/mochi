import Foundation
import Testing

@testable import MochiCore

/// The 书签 window (#123, ADR-0033): search, reorder, edit, add and delete — against a real store.
@Suite struct BookmarkBrowserTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func makeBrowser(_ names: [String] = ["GitHub", "Mochi", "Swift"]) throws -> (BookmarkBrowser, BookmarkStore) {
        let store = BookmarkStore(databaseURL: nil)
        for name in names {
            try store.add(name: name, url: url("https://\(name.lowercased()).example.com/")).get()
        }
        let browser = BookmarkBrowser(store: store) { _ in }
        browser.reload()
        return (browser, store)
    }

    private func names(_ browser: BookmarkBrowser) -> [String] {
        browser.rows.map(\.name)
    }

    private func id(_ name: String, in browser: BookmarkBrowser) throws -> Bookmark.ID {
        try #require(browser.rows.first { $0.name == name }).id
    }

    // MARK: Listing and searching

    @Test func everyBookmarkIsListedInTheUsersOrder() throws {
        let (browser, _) = try makeBrowser()

        #expect(names(browser) == ["GitHub", "Mochi", "Swift"])
        #expect(!browser.isSearching)
    }

    @Test(arguments: [
        (query: "mo", found: ["Mochi"]),
        (query: "HUB", found: ["GitHub"]),
        (query: "example.com", found: ["GitHub", "Mochi", "Swift"]),
        (query: "  swift  ", found: ["Swift"]),
        (query: "nothing", found: []),
        (query: "  ", found: ["GitHub", "Mochi", "Swift"]),
    ])
    func searchingMatchesTheNameOrAddressAnywhere(_ row: (query: String, found: [String])) throws {
        let (browser, _) = try makeBrowser()

        browser.search(row.query)

        #expect(names(browser) == row.found)
    }

    /// An address is searched as it reads (#143), and by its escapes too.
    @Test(arguments: [
        (query: "咖啡", found: ["维基"]),
        (query: "wiki/咖", found: ["维基"]),
        (query: "%E5%92%96", found: ["维基"]),
        (query: "茶", found: []),
    ])
    func searchingMatchesTheAddressAsItReads(_ row: (query: String, found: [String])) throws {
        let (browser, store) = try makeBrowser([])
        try store.add(name: "维基", url: url("https://zh.wikipedia.org/wiki/%E5%92%96%E5%95%A1")).get()

        browser.search(row.query)

        #expect(names(browser) == row.found)
    }

    @Test func aSearchIsKeptAcrossAReload() throws {
        let (browser, store) = try makeBrowser()
        browser.search("mo")
        try store.add(name: "Mozilla", url: url("https://mozilla.org/")).get()

        browser.reload()

        #expect(names(browser) == ["Mochi", "Mozilla"])
    }

    // MARK: Reordering

    @Test(arguments: [
        (moved: ["GitHub"], to: 3, order: ["Mochi", "Swift", "GitHub"]),
        (moved: ["Swift"], to: 0, order: ["Swift", "GitHub", "Mochi"]),
        (moved: ["GitHub", "Swift"], to: 2, order: ["Mochi", "GitHub", "Swift"]),
    ])
    func draggingRowsPutsThemAtThePlaceDropped(_ row: (moved: [String], to: Int, order: [String])) throws {
        let (browser, store) = try makeBrowser()
        let offsets = IndexSet(row.moved.map { name in browser.rows.firstIndex { $0.name == name }! })

        browser.move(fromOffsets: offsets, toOffset: row.to)

        #expect(names(browser) == row.order)
        #expect(store.all().map(\.name) == row.order)
    }

    /// The order is the whole list's: a filtered list can't be dragged.
    @Test func searchResultsCantBeReordered() throws {
        let (browser, store) = try makeBrowser()
        browser.search("i")

        #expect(!browser.canReorder)
        browser.move(fromOffsets: [0], toOffset: 2)

        #expect(store.all().map(\.name) == ["GitHub", "Mochi", "Swift"])
    }

    // MARK: Deleting

    @Test func deletingRemovesTheSelectedBookmarks() throws {
        let (browser, store) = try makeBrowser()

        browser.delete([try id("GitHub", in: browser), try id("Swift", in: browser)])

        #expect(names(browser) == ["Mochi"])
        #expect(store.all().map(\.name) == ["Mochi"])
    }

    // MARK: Adding

    @Test func aNewBookmarkGoesToTheEndWithNoIcon() throws {
        let (browser, store) = try makeBrowser()

        let result = browser.add(name: "Apple", address: "apple.com")

        #expect(names(browser) == ["GitHub", "Mochi", "Swift", "Apple"])
        #expect(store.all().last?.url == url("https://apple.com"))
        #expect(store.all().last?.faviconID == nil)
        #expect(result == .success(try id("Apple", in: browser)))
    }

    /// Addresses are read the way the address bar reads them.
    @Test(arguments: [
        (typed: "github.com/asfamilybank", saved: "https://github.com/asfamilybank"),
        (typed: "http://localhost:3000", saved: "http://localhost:3000"),
        (typed: "  https://a.example.com/x  ", saved: "https://a.example.com/x"),
    ])
    func theAddressIsReadLikeTheAddressBarsAndSaved(_ row: (typed: String, saved: String)) throws {
        let (browser, store) = try makeBrowser([])

        #expect((try? browser.add(name: "A", address: row.typed).get()) != nil)
        #expect(store.all().map(\.url.absoluteString) == [row.saved])
    }

    /// Only web pages: what the address bar would search, or open anywhere but the web, is refused
    /// and nothing is saved.
    @Test(arguments: ["swift testing", "", "   ", "about:blank", "file:///Users/someone/a.html", "mochi"])
    func anythingButAWebAddressIsRefused(_ typed: String) throws {
        let (browser, store) = try makeBrowser([])

        #expect(browser.add(name: "A", address: typed) == .failure(.notAnAddress))
        #expect(store.all().isEmpty)
    }

    @Test func anAddressAlreadyBookmarkedIsRefusedNamingThatBookmark() throws {
        let (browser, store) = try makeBrowser()

        let result = browser.add(name: "Again", address: "https://mochi.example.com/#top")

        #expect(result == .failure(.alreadyBookmarked(try id("Mochi", in: browser))))
        #expect(store.all().count == 3)
    }

    @Test func aBlankNameIsTheAddress() throws {
        let (browser, _) = try makeBrowser([])

        _ = browser.add(name: "  ", address: "apple.com")

        #expect(names(browser) == ["https://apple.com"])
    }

    // MARK: Editing

    @Test func editingChangesTheNameAndAddressInPlace() throws {
        let (browser, store) = try makeBrowser()

        let error = browser.edit(try id("Mochi", in: browser), name: "麻糬", address: "github.com/asfamilybank/mochi")

        #expect(error == nil)
        #expect(names(browser) == ["GitHub", "麻糬", "Swift"])
        #expect(store.all()[1].url == url("https://github.com/asfamilybank/mochi"))
    }

    @Test func editingToAnotherBookmarksAddressIsRefused() throws {
        let (browser, store) = try makeBrowser()

        let error = browser.edit(try id("Mochi", in: browser), name: "麻糬", address: "swift.example.com/")

        #expect(error == .alreadyBookmarked(try id("Swift", in: browser)))
        #expect(store.all().map(\.name) == ["GitHub", "Mochi", "Swift"])
    }

    @Test func editingToSomethingNotAnAddressIsRefused() throws {
        let (browser, store) = try makeBrowser()

        #expect(browser.edit(try id("Mochi", in: browser), name: "麻糬", address: "not an address") == .notAnAddress)
        #expect(store.all().map(\.name) == ["GitHub", "Mochi", "Swift"])
    }

    @Test func editingKeepsTheIcon() throws {
        let store = BookmarkStore(databaseURL: nil)
        let icon = Data([0x89, 0x50])
        let bookmark = try store.add(name: "A", url: url("https://a.example.com/"), favicon: icon).get()
        let browser = BookmarkBrowser(store: store) { _ in }
        browser.reload()

        _ = browser.edit(bookmark.id, name: "B", address: "https://a.example.com/")

        #expect(browser.rows.first?.faviconID.flatMap(browser.favicon) == icon)
    }

    // MARK: Opening and copying

    @Test func openingOneBookmarkOpensItsAddress() throws {
        let store = BookmarkStore(databaseURL: nil)
        let bookmark = try store.add(name: "A", url: url("https://a.example.com/")).get()
        var opened: [URL] = []
        let browser = BookmarkBrowser(store: store) { opened.append($0) }
        browser.reload()

        #expect(browser.canOpen([bookmark.id]))
        browser.open([bookmark.id])

        #expect(opened == [bookmark.url])
    }

    /// The widget shows one page: several bookmarks can't all be opened.
    @Test func severalBookmarksCantBeOpenedOrCopiedAtOnce() throws {
        let (browser, _) = try makeBrowser()
        let two: Set = [try id("GitHub", in: browser), try id("Mochi", in: browser)]

        #expect(!browser.canOpen(two))
        #expect(browser.copiedText(for: two) == nil)
    }

    @Test func copyingOneBookmarkCopiesItsAddress() throws {
        let (browser, _) = try makeBrowser()

        #expect(browser.copiedText(for: [try id("Mochi", in: browser)]) == "https://mochi.example.com/")
    }
}
