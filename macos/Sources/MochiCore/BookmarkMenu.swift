import Foundation

/// What the main menu's 书签 lists below its fixed items (#121, ADR-0033) — every bookmark, in the
/// user's order, rebuilt every time the menu is about to open.
public struct BookmarkMenu: Equatable {
    public struct Item: Equatable {
        public let title: String
        public let url: URL
        /// For `Orchestrator.bookmarkFavicon(_:)`.
        public let faviconID: String?

        public init(title: String, url: URL, faviconID: String?) {
            self.title = title
            self.url = url
            self.faviconID = faviconID
        }
    }

    /// A menu item grows as wide as its title; past this many characters it is cut short — the
    /// same width as the 历史记录 menu's.
    public static let maximumTitleLength = HistoryMenu.maximumTitleLength

    public let items: [Item]

    public static func build(bookmarks: [Bookmark]) -> BookmarkMenu {
        BookmarkMenu(
            items: bookmarks.map { bookmark in
                let name = bookmark.name
                let cut = name.count > maximumTitleLength ? name.prefix(maximumTitleLength - 1) + "…" : name
                return Item(title: String(cut), url: bookmark.url, faviconID: bookmark.faviconID)
            })
    }

    /// ⌘D's title. There is no star in the address bar (ADR-0033), so this is what tells the user
    /// the page is already a bookmark.
    public static func addItemTitle(isCurrentPageBookmarked: Bool) -> String {
        isCurrentPageBookmarked ? "编辑书签…" : "添加书签…"
    }
}
