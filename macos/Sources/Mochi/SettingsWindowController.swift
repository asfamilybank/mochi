import AppKit
import SwiftUI

/// Owns the settings panel's (#13) window — a single persistent instance reused across opens
/// (from either the toolbar's settings entry or the tray's 设置… item), rather than
/// recreated per-request, so its editing state (and the `SettingsViewModel` it observes) survives
/// being closed and reopened.
///
/// Since #65 it is a Safari-style preferences window: `SettingsTabViewController`'s `.toolbar`
/// tab style puts one button per `SettingsPane` into the window's own toolbar, so the strip sits
/// in the titlebar (its empty space drags the window) and the window title follows the selected
/// pane. The window is deliberately not `.resizable` — the width is fixed and each pane's height
/// is its content's, exactly like Safari's settings window.
final class SettingsWindowController: NSWindowController {
    convenience init(viewModel: SettingsViewModel) {
        let tabViewController = SettingsTabViewController(viewModel: viewModel)
        let window = NSWindow(contentViewController: tabViewController)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        self.init(window: window)
        tabViewController.fitWindowToSelectedPane(animated: false)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// One `NSHostingController` per `SettingsPane`, switched by the window toolbar. AppKit leaves the
/// window at whatever size the first pane had, so selecting a pane resizes the window to that
/// pane's natural height itself — keeping the top edge where it is, the way Safari's settings
/// window grows and shrinks downward.
///
/// Switching follows Safari too: the old pane vanishes at once (no crossfade — that reads as a
/// slow dissolve for what is a discrete tab switch), the window resizes empty, and the new pane
/// appears only once the window has reached its size.
private final class SettingsTabViewController: NSTabViewController {
    init(viewModel: SettingsViewModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.allowUserInteraction]
        for pane in SettingsPane.allCases {
            let hostingController = NSHostingController(rootView: pane.content(viewModel: viewModel))
            // Only report the pane's natural size, no min/max constraints: constraints would pin
            // the shared content view to one pane's size and fight the resize below.
            hostingController.sizingOptions = [.preferredContentSize]
            hostingController.title = pane.title
            let item = NSTabViewItem(viewController: hostingController)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelectedPane(animated: view.window?.isVisible == true)
    }

    func fitWindowToSelectedPane(animated: Bool) {
        guard let window = view.window,
            let pane = tabViewItems[selectedTabViewItemIndex].viewController
        else { return }
        pane.view.layoutSubtreeIfNeeded()
        let contentSize = pane.preferredContentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        let frame = window.frame
        let target = NSRect(
            x: frame.minX, y: frame.maxY - newFrame.height, width: newFrame.width, height: newFrame.height)
        guard animated, target != frame else {
            pane.view.isHidden = false
            window.setFrame(target, display: true)
            return
        }
        pane.view.isHidden = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = window.animationResizeTime(target)
            window.animator().setFrame(target, display: true)
        } completionHandler: { [weak self, weak pane] in
            // A quicker click may have moved on to another pane; that one reveals itself.
            guard let self, let pane,
                self.tabViewItems[self.selectedTabViewItemIndex].viewController === pane
            else { return }
            pane.view.isHidden = false
        }
    }
}
