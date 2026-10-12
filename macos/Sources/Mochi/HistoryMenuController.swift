import AppKit
import MochiCore

/// Fills the 历史记录 menu below 返回/前进 (#102) from `Orchestrator.historyMenu()`, rebuilt every
/// time the menu is about to open (`menuNeedsUpdate`), so it is never a snapshot of an earlier
/// moment. Today's pages come straight after the fixed items; each earlier day with any is a
/// submenu named after its date. Picking a page opens it in the widget
/// (`Orchestrator.openFromHistory`), which reopens a closed widget and leaves Ghost Mode alone.
///
/// `NSMenu.delegate` is weak, so `MainMenuBuilder` holds this for the app's lifetime.
final class HistoryMenuController: NSObject, NSMenuDelegate {
    private let orchestrator: Orchestrator
    /// The items the menu was built with — 返回/前进. Everything after them is history.
    private var fixedItemCount = 0
    /// `NSMenuItem.target` doesn't retain; replaced on every rebuild along with the items.
    private var targets: [MenuItemActionTarget] = []

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }

    /// Call once the menu's fixed items are in place.
    func attach(to menu: NSMenu) {
        fixedItemCount = menu.items.count
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.items.count > fixedItemCount {
            menu.removeItem(at: menu.items.count - 1)
        }
        targets = []

        let model = orchestrator.historyMenu()
        guard !model.today.isEmpty || !model.earlierDays.isEmpty else { return }
        menu.addItem(.separator())
        for item in model.today {
            menu.addItem(pageItem(item))
        }
        if !model.today.isEmpty, !model.earlierDays.isEmpty {
            menu.addItem(.separator())
        }
        for day in model.earlierDays {
            let dayItem = NSMenuItem(title: day.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: day.title)
            for item in day.items {
                submenu.addItem(pageItem(item))
            }
            dayItem.submenu = submenu
            menu.addItem(dayItem)
        }
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
