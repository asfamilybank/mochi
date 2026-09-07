import AppKit
import MochiCore

/// Builds `NSApp.mainMenu` (#37, File menu added by #42) — Mochi never set one before, which silently broke every
/// standard editing shortcut (`⌘V`/`⌘C`/`⌘A`/…) since AppKit dispatches those through the main
/// menu's key equivalents, not automatically.
///
/// A class (not a free function) because `NSMenuItem.target` doesn't retain its target — the
/// `MenuItemActionTarget`s built alongside each custom item need somewhere to live for the app's
/// lifetime, and this instance is it (`AppDelegate` holds a strong reference).
final class MainMenuBuilder {
    private var targets: [MenuItemActionTarget] = []

    /// - Parameters:
    ///   - orchestrator: supplies the operations the Mochi/Display menus call — reload, zoom,
    ///     open settings — all already public on `Orchestrator` (#37) rather than reached for via
    ///     new `PlatformOps` methods.
    func build(orchestrator: Orchestrator) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem(orchestrator: orchestrator))
        mainMenu.addItem(fileMenuItem(orchestrator: orchestrator))
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem(orchestrator: orchestrator))
        mainMenu.addItem(windowMenuItem())
        return mainMenu
    }

    // MARK: - Mochi menu

    private func appMenuItem(orchestrator: Orchestrator) -> NSMenuItem {
        let menu = NSMenu(title: AppInfo.name)

        menu.addItem(action("关于 \(AppInfo.name)") {
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: AppInfo.name,
                .applicationVersion: AppInfo.version,
            ])
        })
        menu.addItem(.separator())
        menu.addItem(action("设置…", keyEquivalent: ",") {
            orchestrator.openSettingsPanel()
        })
        menu.addItem(.separator())
        menu.addItem(action("退出 \(AppInfo.name)", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - File menu

    /// One item only (#42): 关闭窗口. Mochi has no concept of new/open/export, so no such items are
    /// invented to fill the menu out. `⌘W` routes to `Orchestrator.closeWidget` (rather than a
    /// responder-chain `performClose:`) so that it means "close the widget" specifically, and is
    /// greyed out — via the standard validation hook, not manual `isEnabled` flips — whenever
    /// there is no widget to close.
    private func fileMenuItem(orchestrator: Orchestrator) -> NSMenuItem {
        let menu = NSMenu(title: "文件")

        menu.addItem(widgetAction("关闭窗口", keyEquivalent: "w", orchestrator: orchestrator) {
            orchestrator.closeWidget()
        })

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Edit menu

    /// Every item routes to the standard `NSText`/`NSResponder` action selectors with `target`
    /// left `nil` so AppKit dispatches along the responder chain to whatever currently holds first
    /// responder (the address bar's field editor, most of the time) — Mochi implements none of
    /// this editing logic itself. "开始听写"/"表情与符号" aren't added here: AppKit appends both
    /// automatically once it finds a menu with a `paste:` action, titled "编辑".
    private func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "编辑")

        menu.addItem(responderChainItem("撤销", selectorName: "undo:", keyEquivalent: "z"))
        menu.addItem(responderChainItem("重做", selectorName: "redo:", keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(responderChainItem("剪切", selectorName: "cut:", keyEquivalent: "x"))
        menu.addItem(responderChainItem("拷贝", selectorName: "copy:", keyEquivalent: "c"))
        menu.addItem(responderChainItem("粘贴", selectorName: "paste:", keyEquivalent: "v"))
        menu.addItem(
            responderChainItem(
                "粘贴并匹配样式", selectorName: "pasteAsPlainText:", keyEquivalent: "v",
                modifierMask: [.command, .option, .shift]))
        menu.addItem(responderChainItem("删除", selectorName: "delete:", keyEquivalent: ""))
        menu.addItem(responderChainItem("全选", selectorName: "selectAll:", keyEquivalent: "a"))

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Display menu

    private func viewMenuItem(orchestrator: Orchestrator) -> NSMenuItem {
        let menu = NSMenu(title: "显示")

        menu.addItem(widgetAction("刷新", keyEquivalent: "r", orchestrator: orchestrator) {
            orchestrator.reloadPage()
        })
        menu.addItem(.separator())
        menu.addItem(widgetAction("放大", keyEquivalent: "+", orchestrator: orchestrator) {
            orchestrator.zoomIn()
        })
        menu.addItem(widgetAction("缩小", keyEquivalent: "-", orchestrator: orchestrator) {
            orchestrator.zoomOut()
        })
        menu.addItem(widgetAction("实际大小", keyEquivalent: "0", orchestrator: orchestrator) {
            orchestrator.resetZoom()
        })

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Window menu

    /// Minimize/Zoom are the only two items this app supplies by hand — everything else (the
    /// window list, "移动与调整大小", "前置全部窗口") is appended automatically by AppKit once
    /// `NSApp.windowsMenu` points at this submenu.
    private func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "窗口")

        let minimize = NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(minimize)
        let zoom = NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(zoom)

        let item = NSMenuItem()
        item.submenu = menu
        NSApp.windowsMenu = menu
        return item
    }

    // MARK: - Item construction

    /// An item that only makes sense while a widget window exists (#42) — validated against
    /// `Orchestrator.hasActiveWidget` every time the menu opens or the key equivalent fires.
    private func widgetAction(
        _ title: String, keyEquivalent: String, orchestrator: Orchestrator, perform: @escaping () -> Void
    ) -> NSMenuItem {
        action(title, keyEquivalent: keyEquivalent, isEnabled: { orchestrator.hasActiveWidget }, perform: perform)
    }

    private func action(
        _ title: String, keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command], isEnabled: @escaping () -> Bool = { true },
        perform: @escaping () -> Void
    ) -> NSMenuItem {
        let target = MenuItemActionTarget(isEnabled: isEnabled, action: perform)
        targets.append(target)
        let item = NSMenuItem(title: title, action: #selector(MenuItemActionTarget.invoke), keyEquivalent: keyEquivalent)
        item.target = target
        item.keyEquivalentModifierMask = modifierMask
        return item
    }

    private func responderChainItem(
        _ title: String, selectorName: String, keyEquivalent: String,
        modifierMask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(selectorName), keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        return item
    }
}
