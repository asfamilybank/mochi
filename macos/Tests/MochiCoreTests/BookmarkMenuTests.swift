import Foundation
import Testing

@testable import MochiCore

/// The main menu's 书签 (#121): the add/edit item, then every bookmark in the user's order.
@Suite struct BookmarkMenuTests {
    private func bookmark(_ id: Bookmark.ID, _ name: String, _ url: String, faviconID: String? = nil) -> Bookmark {
        Bookmark(id: id, name: name, url: URL(string: url)!, faviconID: faviconID)
    }

    @Test func everyBookmarkIsListedInTheUsersOrder() {
        let menu = BookmarkMenu.build(bookmarks: [
            bookmark(2, "Mochi", "https://github.com/asfamilybank/mochi", faviconID: "f"),
            bookmark(1, "GitHub", "https://github.com/"),
        ])

        #expect(
            menu.items == [
                BookmarkMenu.Item(title: "Mochi", url: URL(string: "https://github.com/asfamilybank/mochi")!, faviconID: "f"),
                BookmarkMenu.Item(title: "GitHub", url: URL(string: "https://github.com/")!, faviconID: nil),
            ])
    }

    @Test func aLongNameIsCutShort() {
        let menu = BookmarkMenu.build(bookmarks: [bookmark(1, String(repeating: "长", count: 200), "https://a.example.com/")])

        let shown = menu.items.first?.title ?? ""

        #expect(shown.count == BookmarkMenu.maximumTitleLength)
        #expect(shown.hasSuffix("…"))
    }

    /// No star in the address bar (ADR-0033): the item's own title is what says the page is
    /// already bookmarked.
    @Test(arguments: [(isBookmarked: false, title: "添加书签…"), (isBookmarked: true, title: "编辑书签…")])
    func theAddItemSaysWhetherThePageIsAlreadyBookmarked(_ row: (isBookmarked: Bool, title: String)) {
        #expect(BookmarkMenu.addItemTitle(isCurrentPageBookmarked: row.isBookmarked) == row.title)
    }

    /// ⌘D belongs to the 书签 menu, so no global hotkey or mapping may take it.
    @Test func addBookmarkIsAReservedMenuShortcut() {
        let addBookmark = Hotkey(keyCode: 0x02, modifierFlags: 0x0100)
        #expect(DefaultHotkeys.addBookmark == addBookmark)
        #expect(HotkeyDisplay.describe(addBookmark) == "⌘D")
        #expect(DefaultHotkeys.reservedLocalMenuShortcuts.contains(addBookmark))
    }
}
