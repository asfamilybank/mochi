import Foundation

public protocol WidgetWindowHandle {}

/// One entry in the tray (menu-bar) icon's menu (#9) — a title paired with the action to run
/// when it's clicked. Not `Equatable` since `action` is a closure; tests compare `.title` and
/// invoke `.action` directly to observe its effect instead.
public struct TrayMenuItem {
    public let title: String
    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

public protocol PlatformOps: AnyObject {
    func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle
    func loadURL(_ url: URL, in window: WidgetWindowHandle)
    func showWindow(_ window: WidgetWindowHandle)
    func applyZoom(_ zoom: Double, in window: WidgetWindowHandle)
    func captureWindowState(of window: WidgetWindowHandle) -> WindowState
    func onWindowWillClose(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// The visible frame of every connected screen. Index 0 is always the primary
    /// (menu-bar) screen — matches `NSScreen.screens`' documented ordering.
    func visibleScreens() -> [CGRect]

    func setToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the user manually navigates via the toolbar's
    /// address bar (as opposed to a programmatic `loadURL` call).
    func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void)

    /// Applies a pinned (always-on-top) state, independent of Normal/Ghost Mode. Used both to
    /// restore a persisted pinned state on launch and to reflect toggles back into the window.
    func setPinned(_ pinned: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the user toggles the window's Pin control, so the new
    /// state can be persisted.
    func onPinnedChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void)

    /// Evaluates `source` in the page's JavaScript context. Callers are expected to only call
    /// this once a page has finished loading (see `onNavigationFinished`).
    func injectScript(_ source: String, in window: WidgetWindowHandle)

    /// Registers a handler invoked every time a page load finishes, so scripts can be
    /// (re-)injected after each navigation, not just the first.
    func onNavigationFinished(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Toggles the native title bar + custom toolbar row's presence via the window's `styleMask`
    /// (ADR-0004) — Ghost Mode's "no chrome at all" look. Distinct from `setToolbarVisible`,
    /// which only ever hides the custom row and leaves native decorations alone.
    func setNativeChromeVisible(_ visible: Bool, in window: WidgetWindowHandle)

    /// Sets the window's overall content opacity toward Ghost Mode's configured target (1.0 is
    /// fully opaque Normal Mode). Implemented via `NSWindow.alphaValue` plus the WKWebView
    /// `drawsBackground` private-API hack (ADR-0001) needed to let anything below alpha 1.0
    /// show through at all.
    func setContentOpacity(_ opacity: Double, in window: WidgetWindowHandle)

    /// Enables/disables `NSWindow.ignoresMouseEvents` — Ghost Mode's click-through behavior.
    func setMousePassthrough(_ enabled: Bool, in window: WidgetWindowHandle)

    /// Fully hides/unhides the window (content stops rendering while hidden, per the domain
    /// doc) — distinct from mouse passthrough, which stays interactive-but-invisible-to-clicks.
    func setWindowHidden(_ hidden: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the mouse enters the widget's area, regardless of mode —
    /// callers are responsible for ignoring it outside Ghost Mode.
    func onMouseEntered(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Registers a system-wide hotkey and returns whether registration succeeded (`false` when
    /// another application already holds that combination) — callers must surface failure to the
    /// user rather than silently dropping it.
    @discardableResult
    func registerGlobalHotkey(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool

    /// Surfaces a user-facing alert — used for conditions like a hotkey conflict that must not
    /// fail silently.
    func presentAlert(title: String, message: String)

    /// Sets the magnetic edge/corner snap distance (#6) applied on every drag step.
    func setSnapThreshold(_ threshold: Double, in window: WidgetWindowHandle)

    /// Creates the app's persistent menu-bar (tray) icon (#9) — present for the app's entire
    /// lifetime regardless of Normal/Ghost Mode — populated with `items` in order. Not tied to a
    /// `WidgetWindowHandle` since the tray icon is app-global, not per-window. Called once, at
    /// launch.
    func createTrayIcon(items: [TrayMenuItem])

    /// Terminates the app — the tray icon's "Quit" entry (#9) must work on its own, since Ghost
    /// Mode can leave every window fully hidden with no other way to reach a quit control.
    func terminateApp()
}
