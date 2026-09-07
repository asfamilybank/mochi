import AppKit

/// Bridges a closure to the `@objc`/target-action mechanism `NSMenuItem` requires — shared by
/// the tray icon's menu (`AppKitPlatformOps.createTrayIcon`) and the app's main menu
/// (`MainMenuBuilder`, in the `Mochi` target; `public` so that other module can see it).
/// `NSMenuItem.target` doesn't retain its target, so whichever menu builds one of these must
/// keep it alive itself for as long as that menu exists.
///
/// `isEnabled` plugs into AppKit's standard menu validation (`NSMenuItemValidation`, consulted
/// every time the menu is about to show or the key equivalent is pressed) — how the main menu
/// greys out the items that need a widget while the widget is closed (#42), rather than anyone
/// flipping `NSMenuItem.isEnabled` by hand at the right moments.
public final class MenuItemActionTarget: NSObject, NSMenuItemValidation {
    private let action: () -> Void
    private let isEnabled: () -> Bool

    public init(isEnabled: @escaping () -> Bool = { true }, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    @objc public func invoke() {
        action()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isEnabled()
    }
}
