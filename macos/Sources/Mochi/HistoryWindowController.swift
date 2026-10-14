import AppKit
import Combine
import MochiCore
import SwiftUI

/// The 历史记录 window (#108): an ordinary window, like 设置, so opening it neither covers nor
/// interrupts the widget — whatever is playing there keeps playing, Ghost Mode included. AppKit
/// window and toolbar (with the search field), SwiftUI list (ADR-0018).
///
/// One instance for the app's lifetime, created on first use by `MainMenuBuilder`; closing only
/// orders it out, so the search survives a close and reopen.
final class HistoryWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let searchItemIdentifier = NSToolbarItem.Identifier("history.search")
    private static let clearItemIdentifier = NSToolbarItem.Identifier("history.clear")
    private static let matchCountItemIdentifier = NSToolbarItem.Identifier("history.matchCount")

    private let model: HistoryViewModel
    /// Made by the toolbar, kept to swap with each other as a search starts and ends (#118).
    private weak var clearItem: NSToolbarItem?
    private weak var matchCountItem: NSToolbarItem?
    private let matchCountLabel = NSTextField(labelWithString: "")
    private weak var searchField: NSSearchField?
    private var subscriptions: Set<AnyCancellable> = []
    /// `PlatformOps.activateApp` — activation goes through the platform seam, never straight to
    /// `NSApp` (CLAUDE.md).
    private let activateApp: () -> Void

    /// - Parameter clearBrowsingData: `SettingsController.clearBrowsingData`, for 清除历史记录… (#115).
    init(
        browser: HistoryBrowser, activateApp: @escaping () -> Void,
        clearBrowsingData: @escaping BrowsingDataClearing
    ) {
        model = HistoryViewModel(browser: browser, clearBrowsingData: clearBrowsingData)
        self.activateApp = activateApp
        let hostingController = NSHostingController(rootView: HistoryView(model: model))
        // Only the minimum: the window is resizable and the list fills whatever it is given.
        hostingController.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "历史记录"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 640, height: 520))
        window.center()
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "History")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.delegate = self

        matchCountLabel.textColor = .secondaryLabelColor
        // #118: while searching, 「N 个匹配项」 takes 清除历史记录…'s place, as in Safari.
        model.$isSearching.combineLatest(model.$matchCount)
            .sink { [weak self] isSearching, count in self?.showSearchState(isSearching: isSearching, matchCount: count) }
            .store(in: &subscriptions)
        // A query set from elsewhere (显示此网站的所有记录, #119) shows in the field too.
        model.$query
            .sink { [weak self] query in
                guard let field = self?.searchField, field.stringValue != query else { return }
                field.stringValue = query
            }
            .store(in: &subscriptions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ⌘Y: brings the window forward, or closes it when it already is the one in front.
    func toggle() {
        guard let window else { return }
        if window.isVisible, window.isKeyWindow, NSApp.isActive {
            window.performClose(nil)
        } else {
            // #110: 移除历史记录项目 applies as the window opens, before anything is listed; and
            // the window always opens on today alone unfolded (#116).
            model.removeExpiredVisits()
            model.resetExpansion()
            window.makeKeyAndOrderFront(nil)
            activateApp()
        }
    }

    // MARK: NSWindowDelegate

    /// Pages visited while the window was in the back show up when it comes forward again.
    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.matchCountItemIdentifier, Self.clearItemIdentifier, Self.searchItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Self.clearItemIdentifier {
            // #115: Safari's place for it, just left of the search field.
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.title = "清除历史记录…"
            item.label = "清除历史记录"
            item.toolTip = "清除历史记录，也可以选择一并清除网站数据"
            item.isBordered = true
            item.target = self
            item.action = #selector(clearHistory(_:))
            item.isHidden = model.isSearching
            clearItem = item
            return item
        }
        if itemIdentifier == Self.matchCountItemIdentifier {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "匹配项"
            item.view = matchCountLabel
            item.isHidden = !model.isSearching
            matchCountItem = item
            return item
        }
        guard itemIdentifier == Self.searchItemIdentifier else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
        item.searchField.placeholderString = "搜索历史记录"
        item.searchField.target = self
        item.searchField.action = #selector(searchChanged(_:))
        item.searchField.stringValue = model.query
        searchField = item.searchField
        return item
    }

    /// Fires as the user types (`NSSearchField` sends incrementally) and when the clear button
    /// empties the field.
    @objc private func searchChanged(_ sender: NSSearchField) {
        model.query = sender.stringValue
    }

    private func showSearchState(isSearching: Bool, matchCount: Int) {
        matchCountLabel.stringValue = "\(matchCount) 个匹配项"
        clearItem?.isHidden = isSearching
        matchCountItem?.isHidden = !isSearching
    }

    @objc private func clearHistory(_ sender: Any?) {
        model.isClearingHistory = true
    }
}
