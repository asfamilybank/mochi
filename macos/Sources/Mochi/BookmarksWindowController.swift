import AppKit
import MochiCore
import SwiftUI

/// The 书签 window (#123, ADR-0033): an ordinary window, like 历史记录, so opening it neither covers
/// nor interrupts the widget. AppKit window and toolbar (新建书签 and the search field), SwiftUI
/// list (ADR-0018).
///
/// One instance for the app's lifetime, created on first use by `MainMenuBuilder`; closing only
/// orders it out.
final class BookmarksWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSMenuItemValidation
{
    private static let searchItemIdentifier = NSToolbarItem.Identifier("bookmarks.search")
    private static let addItemIdentifier = NSToolbarItem.Identifier("bookmarks.add")

    private let model: BookmarksViewModel
    /// `PlatformOps.activateApp` — activation goes through the platform seam (CLAUDE.md).
    private let activateApp: () -> Void

    init(browser: BookmarkBrowser, activateApp: @escaping () -> Void) {
        model = BookmarksViewModel(browser: browser)
        self.activateApp = activateApp
        let hostingController = NSHostingController(rootView: BookmarksView(model: model))
        hostingController.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "书签"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "Bookmarks")
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

    /// ⌥⌘B: brings the window forward, or closes it when it already is the one in front.
    func toggle() {
        guard let window else { return }
        if window.isVisible, window.isKeyWindow, NSApp.isActive {
            window.performClose(nil)
        } else {
            model.reload()
            window.makeKeyAndOrderFront(nil)
            activateApp()
        }
    }

    // MARK: NSWindowDelegate

    /// Bookmarks added with ⌘D while the window was in the back show up when it comes forward.
    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.addItemIdentifier, Self.searchItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Self.addItemIdentifier {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建书签")
            item.label = "新建书签"
            item.toolTip = "新建书签"
            item.isBordered = true
            item.target = self
            item.action = #selector(addBookmark(_:))
            return item
        }
        guard itemIdentifier == Self.searchItemIdentifier else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
        item.searchField.placeholderString = "搜索书签"
        item.searchField.target = self
        item.searchField.action = #selector(searchChanged(_:))
        return item
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        model.query = sender.stringValue
    }

    @objc private func addBookmark(_ sender: Any?) {
        model.beginAdding()
    }

    // MARK: ⌘C

    /// As in the 历史记录 window (#119): the controller is on the window's responder chain behind
    /// the search field's editor, and with several rows selected nothing is copied.
    @objc func copy(_ sender: Any?) {
        model.copy(model.selection)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(copy(_:)) else { return true }
        return model.canCopy(model.selection)
    }
}
