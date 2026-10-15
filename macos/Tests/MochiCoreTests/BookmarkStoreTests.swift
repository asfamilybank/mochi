import Foundation
import Testing

@testable import MochiCore

/// 书签 (#121, ADR-0033): one flat, hand-ordered list, one bookmark per address, kept in its own
/// file.
@Suite struct BookmarkStoreTests {
    private let iconA = Data([0x89, 0x50, 0x4E, 0x47, 0xA])
    private let iconB = Data([0x89, 0x50, 0x4E, 0x47, 0xB])

    private func url(_ string: String) -> URL { URL(string: string)! }

    private func names(_ store: BookmarkStore) -> [String] {
        store.all().map(\.name)
    }

    // MARK: Adding

    @Test func aNewBookmarkGoesToTheEndOfTheList() throws {
        let store = BookmarkStore(databaseURL: nil)

        let first = try store.add(name: "GitHub", url: url("https://github.com/")).get()
        try store.add(name: "Mochi", url: url("https://github.com/asfamilybank/mochi")).get()

        #expect(names(store) == ["GitHub", "Mochi"])
        #expect(store.all().first == first)
        #expect(first.url == url("https://github.com/"))
        #expect(first.faviconID == nil)
    }

    /// One bookmark per address: adding the same address again is refused and names the bookmark
    /// it already is.
    @Test func anAddressCanBeBookmarkedOnlyOnce() throws {
        let store = BookmarkStore(databaseURL: nil)
        let existing = try store.add(name: "GitHub", url: url("https://github.com/")).get()

        let again = store.add(name: "Again", url: url("https://github.com/"))

        #expect(again == .failure(.alreadyBookmarked(existing)))
        #expect(names(store) == ["GitHub"])
    }

    /// A fragment only points somewhere inside the same page — the same rule history keys visits by.
    @Test func theFragmentIsNotPartOfTheAddress() throws {
        let store = BookmarkStore(databaseURL: nil)
        let existing = try store.add(name: "Docs", url: url("https://example.com/docs#intro")).get()

        #expect(existing.url == url("https://example.com/docs"))
        #expect(store.bookmark(for: url("https://example.com/docs#usage")) == existing)
        #expect(store.add(name: "Again", url: url("https://example.com/docs#usage")) == .failure(.alreadyBookmarked(existing)))
    }

    @Test(arguments: [
        (stored: "https://example.com/a", asked: "https://example.com/a", isFound: true),
        (stored: "https://example.com/a", asked: "https://example.com/a?x=1", isFound: false),
        (stored: "https://example.com/a", asked: "https://example.com/b", isFound: false),
        (stored: "https://example.com/a?x=1", asked: "https://example.com/a?x=1", isFound: true),
    ])
    func aBookmarkIsFoundByItsWholeAddress(_ row: (stored: String, asked: String, isFound: Bool)) throws {
        let store = BookmarkStore(databaseURL: nil)
        let stored = try store.add(name: "A", url: url(row.stored)).get()

        #expect(store.bookmark(for: url(row.asked)) == (row.isFound ? stored : nil))
    }

    // MARK: Changing

    @Test func renamingChangesOnlyTheName() throws {
        let store = BookmarkStore(databaseURL: nil)
        let bookmark = try store.add(name: "GitHub", url: url("https://github.com/")).get()

        store.rename(bookmark.id, to: "代码")

        #expect(store.all() == [Bookmark(id: bookmark.id, name: "代码", url: bookmark.url, faviconID: nil)])
    }

    @Test func changingTheAddressKeepsThePlaceInTheList() throws {
        let store = BookmarkStore(databaseURL: nil)
        let a = try store.add(name: "A", url: url("https://a.example.com/")).get()
        try store.add(name: "B", url: url("https://b.example.com/")).get()

        let result = store.changeURL(a.id, to: url("https://new.example.com/#x"))

        #expect(result == nil)
        #expect(store.all().map(\.url.absoluteString) == ["https://new.example.com/", "https://b.example.com/"])
    }

    @Test func changingTheAddressToAnotherBookmarksIsRefused() throws {
        let store = BookmarkStore(databaseURL: nil)
        let a = try store.add(name: "A", url: url("https://a.example.com/")).get()
        let b = try store.add(name: "B", url: url("https://b.example.com/")).get()

        let result = store.changeURL(a.id, to: url("https://b.example.com/"))

        #expect(result == .alreadyBookmarked(b))
        #expect(store.all().map(\.url) == [a.url, b.url])
    }

    /// Changing a bookmark's address to the one it already has is no conflict with itself.
    @Test func changingTheAddressToItsOwnIsFine() throws {
        let store = BookmarkStore(databaseURL: nil)
        let a = try store.add(name: "A", url: url("https://a.example.com/")).get()

        #expect(store.changeURL(a.id, to: url("https://a.example.com/#top")) == nil)
    }

    @Test(arguments: [
        (moved: "A", to: 2, order: ["B", "C", "A"]),
        (moved: "C", to: 0, order: ["C", "A", "B"]),
        (moved: "B", to: 1, order: ["A", "B", "C"]),
        (moved: "A", to: 9, order: ["B", "C", "A"]),
    ])
    func movingABookmarkPutsItAtThatPlace(_ row: (moved: String, to: Int, order: [String])) throws {
        let store = BookmarkStore(databaseURL: nil)
        for name in ["A", "B", "C"] {
            try store.add(name: name, url: url("https://\(name.lowercased()).example.com/")).get()
        }
        let moved = try #require(store.all().first { $0.name == row.moved })

        store.move(moved.id, to: row.to)

        #expect(names(store) == row.order)
    }

    @Test func deletingRemovesExactlyThoseBookmarks() throws {
        let store = BookmarkStore(databaseURL: nil)
        let a = try store.add(name: "A", url: url("https://a.example.com/")).get()
        try store.add(name: "B", url: url("https://b.example.com/")).get()
        let c = try store.add(name: "C", url: url("https://c.example.com/")).get()

        store.delete([a.id, c.id])

        #expect(names(store) == ["B"])
        #expect(store.add(name: "A", url: a.url).map(\.name) == .success("A"))
        #expect(names(store) == ["B", "A"])
    }

    // MARK: Site icons

    @Test func aBookmarkKeepsTheIconItWasAddedWith() throws {
        let store = BookmarkStore(databaseURL: nil)

        let bookmark = try store.add(name: "A", url: url("https://a.example.com/"), favicon: iconA).get()

        #expect(bookmark.faviconID.flatMap(store.favicon) == iconA)
    }

    @Test func anIconCanBeReplacedLater() throws {
        let store = BookmarkStore(databaseURL: nil)
        let bookmark = try store.add(name: "A", url: url("https://a.example.com/"), favicon: iconA).get()

        store.updateFavicon(iconB, of: bookmark.id)

        let updated = try #require(store.all().first)
        #expect(updated.faviconID != bookmark.faviconID)
        #expect(updated.faviconID.flatMap(store.favicon) == iconB)
    }

    // MARK: On disk

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func bookmarksSurviveReopeningTheFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Bookmarks.db")

        do {
            let store = BookmarkStore(databaseURL: file)
            try store.add(name: "A", url: url("https://a.example.com/"), favicon: iconA).get()
            try store.add(name: "B", url: url("https://b.example.com/")).get()
        }
        let reopened = BookmarkStore(databaseURL: file)

        #expect(names(reopened) == ["A", "B"])
        #expect(reopened.all().first?.faviconID.flatMap(reopened.favicon) == iconA)
    }

    /// Bookmarks live in a file of their own, beside history's (ADR-0033).
    @Test func theFileSitsBesideHistory() {
        #expect(BookmarkStore.defaultDatabaseURL.lastPathComponent == "Bookmarks.db")
        #expect(
            BookmarkStore.defaultDatabaseURL.deletingLastPathComponent()
                == HistoryStore.defaultDatabaseURL.deletingLastPathComponent())
    }

    /// A damaged file never stands in the way of launching: moved aside, and the list starts empty.
    @Test func aCorruptFileIsMovedAsideAndTheListStartsOverEmpty() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Bookmarks.db")
        let garbage = Data(repeating: 0x5A, count: 8192)
        try garbage.write(to: file)

        let store = BookmarkStore(databaseURL: file)

        #expect(store.all().isEmpty)
        try store.add(name: "A", url: url("https://a.example.com/")).get()
        #expect(names(store) == ["A"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("Bookmarks.db.corrupt")) == garbage)
    }
}
