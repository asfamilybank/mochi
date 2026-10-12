import AppKit
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

    private let model: HistoryViewModel

    init(browser: HistoryBrowser) {
        model = HistoryViewModel(browser: browser)
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
            // #110: 移除历史记录项目 applies as the window opens, before anything is listed.
            model.removeExpiredEntries()
            model.reload()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: NSWindowDelegate

    /// Pages visited while the window was in the back show up when it comes forward again.
    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.searchItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.searchItemIdentifier else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
        item.searchField.placeholderString = "搜索历史记录"
        item.searchField.target = self
        item.searchField.action = #selector(searchChanged(_:))
        item.searchField.stringValue = model.query
        return item
    }

    /// Fires as the user types (`NSSearchField` sends incrementally) and when the clear button
    /// empties the field.
    @objc private func searchChanged(_ sender: NSSearchField) {
        model.query = sender.stringValue
    }
}
