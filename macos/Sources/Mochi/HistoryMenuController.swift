import AppKit
import MochiCore

/// Fills the 历史记录 menu below 返回/前进 (#102) from `Orchestrator.historyMenu()`, rebuilt every
/// time the menu is about to open (`menuNeedsUpdate`), so it is never a snapshot of an earlier
/// moment. Today's pages come straight after the leading fixed items; each earlier day with any is
/// a submenu named after its date. Items added after `attach(to:)` (显示全部历史记录, #108) stay
/// at the bottom, below the list. Picking a page opens it in the widget
/// (`Orchestrator.openFromHistory`), which reopens a closed widget and leaves Ghost Mode alone.
///
/// `NSMenu.delegate` is weak, so `MainMenuBuilder` holds this for the app's lifetime.
final class HistoryMenuController: NSObject, NSMenuDelegate {
    private let orchestrator: Orchestrator
    /// The items the menu was built with — 返回/前进. The history list goes right after them.
    private var fixedItemCount = 0
    /// The list as last built — what the next rebuild removes, leaving the items around it.
    private var listItems: [NSMenuItem] = []
    /// `NSMenuItem.target` doesn't retain; replaced on every rebuild along with the items.
    private var targets: [MenuItemActionTarget] = []

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }

    /// Call once the menu's leading fixed items are in place; anything added afterwards stays
    /// below the list.
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

        let model = orchestrator.historyMenu()
        guard !model.today.isEmpty || !model.earlierDays.isEmpty else { return }
        add(.separator(), to: menu)
        for item in model.today {
            add(pageItem(item), to: menu)
        }
        if !model.today.isEmpty, !model.earlierDays.isEmpty {
            add(.separator(), to: menu)
        }
        for day in model.earlierDays {
            let dayItem = NSMenuItem(title: day.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: day.title)
            for item in day.items {
                submenu.addItem(pageItem(item))
            }
            dayItem.submenu = submenu
            add(dayItem, to: menu)
        }
    }

    /// Inserts `item` at the end of the list — after the leading fixed items and whatever of the
    /// list is already in, before the trailing fixed items.
    private func add(_ item: NSMenuItem, to menu: NSMenu) {
        menu.insertItem(item, at: fixedItemCount + listItems.count)
        listItems.append(item)
    }

    private func pageItem(_ item: HistoryMenu.Item) -> NSMenuItem {
        let url = item.url
        let target = MenuItemActionTarget { [orchestrator] in orchestrator.openFromHistory(url) }
        targets.append(target)
        let menuItem = NSMenuItem(title: item.title, action: #selector(MenuItemActionTarget.invoke), keyEquivalent: "")
        menuItem.target = target
        menuItem.toolTip = url.absoluteString
        return menuItem
    }
}
