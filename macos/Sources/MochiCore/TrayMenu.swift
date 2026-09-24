import AppKit

/// The tray's `NSMenu` (#63): built once from `TrayMenuItem`s, and re-synced from their closures
/// every time it is about to open — checkmarks, greyed-out states and hotkey hints are never a
/// snapshot of launch.
///
/// **Hints are display only.** A hint is drawn by setting the item's `keyEquivalent` and
/// modifier mask, the only way to put a combo in AppKit's own key-equivalent column (right
/// aligned, in the menu's shortcut font; an option-only combo like ⌥G renders as "⌥G"). A key
/// equivalent is also something AppKit *matches*, though, and the global hotkeys already fire
/// through Carbon — two paths would run one keypress's action twice. Two guards keep it a
/// picture:
/// - `menuHasKeyEquivalent` answers `false`, so while the menu is closed AppKit never searches it
///   for a match (a status item's menu is not in the main-menu key-equivalent path anyway; this
///   makes it explicit and also spares a full re-sync on every keystroke).
/// - While the menu is open, a keypress can still select an item by its key equivalent; the
///   action of a hinted item ignores activations whose triggering event is a key press, so only
///   a click runs it. The Carbon hotkey — if it fires during menu tracking — is then the single
///   path, as it is everywhere else.
///
/// Quit is the exception to the second guard: an item wearing `.appQuit` goes through the
/// standard `terminate:` (that selector is what earns it the system's Quit icon), and ⌘Q is not a
/// global hotkey, so there is nothing for it to double up with.
final class TrayMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let entries: [(item: TrayMenuItem, menuItem: NSMenuItem)]
    /// `NSMenuItem.target` doesn't retain its target.
    private let targets: [MenuItemActionTarget]

    init(items: [TrayMenuItem]) {
        var entries: [(item: TrayMenuItem, menuItem: NSMenuItem)] = []
        var targets: [MenuItemActionTarget] = []
        for item in items {
            if item.isSeparator {
                entries.append((item, .separator()))
                continue
            }
            let menuItem: NSMenuItem
            if item.icon == .appQuit {
                // No target, exactly like the App menu's 退出: the responder chain ends at NSApp.
                menuItem = NSMenuItem(title: item.title, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            } else {
                let action = item.action
                let target = MenuItemActionTarget(isEnabled: item.isEnabled) {
                    // A key-equivalent match inside the open menu, not a click: the Carbon
                    // hotkey owns keyboard activation (see the type's doc comment).
                    if NSApp.currentEvent?.type == .keyDown { return }
                    action()
                }
                targets.append(target)
                menuItem = NSMenuItem(title: item.title, action: #selector(MenuItemActionTarget.invoke), keyEquivalent: "")
                menuItem.target = target
            }
            menuItem.image = Self.image(for: item.icon, title: item.title)
            entries.append((item, menuItem))
        }
        self.entries = entries
        self.targets = targets
        super.init()
        for entry in entries { menu.addItem(entry.menuItem) }
        menu.delegate = self
        sync()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        sync()
    }

    func menuHasKeyEquivalent(
        _ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        action: UnsafeMutablePointer<Selector?>
    ) -> Bool {
        false
    }

    // MARK: -

    /// Pulls every closure's current answer into the menu items. Enabled state rides on menu
    /// validation (`MenuItemActionTarget.validateMenuItem`, and `NSApplication`'s own for quit),
    /// which AppKit runs as the menu opens.
    private func sync() {
        for (item, menuItem) in entries where !item.isSeparator {
            menuItem.state = item.isChecked() ? .on : .off
            if let hint = item.hotkeyHint(), let key = HotkeyDisplay.menuKeyEquivalent(for: hint) {
                menuItem.keyEquivalent = key
                menuItem.keyEquivalentModifierMask = Self.modifierMask(forCarbonFlags: hint.modifierFlags)
            } else {
                menuItem.keyEquivalent = ""
                menuItem.keyEquivalentModifierMask = []
            }
        }
    }

    private static func image(for icon: TrayMenuIcon?, title: String) -> NSImage? {
        switch icon {
        case .symbol(let name):
            // Default symbol configuration, like the App menu's items: AppKit sizes it to the
            // menu font (13pt on macOS 26).
            return ToolbarStyle.symbolImage(name, accessibilityDescription: title)
        case .ghost:
            return ToolbarStyle.ghostImage(
                pointSize: ToolbarStyle.GlyphSize.trayMenuItem, accessibilityDescription: title)
        case .appQuit, nil:
            // `.appQuit`: AppKit draws the Quit icon itself for a `terminate:` item.
            return nil
        }
    }

    /// Carbon's modifier bits (as `Hotkey` stores them) to AppKit's.
    private static func modifierMask(forCarbonFlags flags: UInt32) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if flags & 0x1000 != 0 { mask.insert(.control) }
        if flags & 0x0800 != 0 { mask.insert(.option) }
        if flags & 0x0200 != 0 { mask.insert(.shift) }
        if flags & 0x0100 != 0 { mask.insert(.command) }
        return mask
    }
}
