import AppKit

/// Bridges a closure to the `@objc`/target-action mechanism `NSMenuItem` requires — shared by
/// the tray icon's menu (`AppKitPlatformOps.createTrayIcon`) and the app's main menu
/// (`MainMenuBuilder`, in the `Mochi` target; `public` so that other module can see it).
/// `NSMenuItem.target` doesn't retain its target, so whichever menu builds one of these must
/// keep it alive itself for as long as that menu exists.
public final class MenuItemActionTarget: NSObject {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc public func invoke() {
        action()
    }
}
