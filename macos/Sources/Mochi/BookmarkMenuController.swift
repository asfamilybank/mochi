import AppKit
import MochiCore

/// Fills the 书签 menu below its fixed items (#121, ADR-0033) from `Orchestrator.bookmarkMenu()`,
/// rebuilt every time the menu is about to open (`menuNeedsUpdate`) — so an edit made anywhere
/// shows the next time it opens. Picking a bookmark opens it in the widget
/// (`Orchestrator.openBookmark`), which reopens a closed widget and leaves Ghost Mode alone.
///
/// `NSMenu.delegate` is weak, so `MainMenuBuilder` holds this for the app's lifetime.
final class BookmarkMenuController: NSObject, NSMenuDelegate {
    private let orchestrator: Orchestrator
    /// The items the menu was built with. The bookmark list goes after them.
    private var fixedItemCount = 0
    /// The list as last built — what the next rebuild removes.
    private var listItems: [NSMenuItem] = []
    /// `NSMenuItem.target` doesn't retain; replaced on every rebuild along with the items.
    private var targets: [MenuItemActionTarget] = []
    private let icons: HistoryFaviconImages

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
        icons = HistoryFaviconImages(png: orchestrator.bookmarkFavicon)
    }

    /// Call once the menu's fixed items are in place.
    func attach(to menu: NSMenu) {
        fixedItemCount = menu.items.count
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in listItems where item.menu === menu {
            menu.removeItem(item)
        }
        listItems = []
        targets = []

        let model = orchestrator.bookmarkMenu()
        guard !model.items.isEmpty else { return }
        add(.separator(), to: menu)
        for item in model.items {
            add(bookmarkItem(item), to: menu)
        }
    }

    private func add(_ item: NSMenuItem, to menu: NSMenu) {
        menu.insertItem(item, at: fixedItemCount + listItems.count)
        listItems.append(item)
    }

    private func bookmarkItem(_ item: BookmarkMenu.Item) -> NSMenuItem {
        let url = item.url
        let target = MenuItemActionTarget { [orchestrator] in orchestrator.openBookmark(url) }
        targets.append(target)
        let menuItem = NSMenuItem(title: item.title, action: #selector(MenuItemActionTarget.invoke), keyEquivalent: "")
        menuItem.target = target
        menuItem.toolTip = URLDisplay.text(of: url)
        // The bookmark's own icon, or the globe history shows for a page without one.
        menuItem.image = icons.image(for: item.faviconID)
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        return menuItem
    }
}
