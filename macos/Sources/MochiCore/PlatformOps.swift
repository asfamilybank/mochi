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

    /// Shows the Empty Page's native content (#16) in place of the page area — the
    /// no-startup-target-and-no-history fallback, and the explicit "空页面" startup choice.
    /// Callers switch back to a real page by calling `loadURL`, which is responsible for hiding
    /// this content again.
    func showEmptyPageContent(in window: WidgetWindowHandle)

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

    /// Registers a handler invoked when the user clicks the toolbar's settings entry (#13) —
    /// mirrors the tray icon's existing "打开设置" entry, giving Normal Mode a second way to reach
    /// the same settings panel.
    func onSettingsRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Evaluates `source` in the page's JavaScript context. Callers are expected to only call
    /// this once a page has finished loading (see `onNavigationFinished`).
    func injectScript(_ source: String, in window: WidgetWindowHandle)

    /// Registers a handler invoked every time a page load finishes, so scripts can be
    /// (re-)injected after each navigation, not just the first.
    func onNavigationFinished(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Registers a handler invoked whenever the loaded page's title changes (`WKWebView.title`
    /// KVO), `nil` while no page has reported one yet. Drives the window's dynamic title (#18,
    /// `AddressBarController`) independently of the Normal Mode toolbar's own Smart Address Field
    /// display, which reads the same underlying signal directly inside the AppKit view.
    func onPageTitleChanged(_ window: WidgetWindowHandle, perform handler: @escaping (String?) -> Void)

    /// Registers a handler invoked whenever the page's loading state changes (`WKWebView.isLoading`
    /// KVO). The Normal Mode toolbar's own Smart Address Field and Loading Progress Bar (#18)
    /// react to this same signal directly inside the AppKit view (they already own `webView`); this
    /// hook exists so other, PlatformOps-only callers can observe loading state too, per the
    /// project's "toolbar-observable state goes through PlatformOps" convention (#4) — see
    /// `onPageTitleChanged`'s equivalent split for the title signal.
    func onLoadingStateChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void)

    /// Registers a handler invoked as the page's load progresses (`WKWebView.estimatedProgress`
    /// KVO, `0.0...1.0`). Same split as `onLoadingStateChanged`: the toolbar's own Loading Progress
    /// Bar (#18) reads `estimatedProgress` directly inside the AppKit view rather than through
    /// this hook.
    func onLoadingProgressChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Double) -> Void)

    /// Sets the window's title (`NSWindow.title`), surfaced in Mission Control/Cmd-Tab (#18).
    /// Callers must always pass a non-empty fallback — see `AddressFieldPresenter.windowTitle`.
    func setWindowTitle(_ title: String, in window: WidgetWindowHandle)

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

    /// Shows/hides Ghost Mode's summoned toolbar overlay (#10) — a small floating capsule built
    /// from its own button instances, independent of the Normal Mode toolbar, that floats above
    /// the page without resizing or repositioning the window.
    func setSummonedToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the user clicks the summoned toolbar's Ghost Mode toggle
    /// button. Routed back through the caller (`GhostModeController.toggle()`) rather than
    /// handled inside the window itself, since — unlike Pin/Refresh — the overlay view has no
    /// self-contained notion of Ghost Mode to flip.
    func onSummonedToolbarGhostModeToggleRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Reloads the widget's currently-loaded page — the default 刷新页面 hotkey's (#12) action.
    func reloadPage(in window: WidgetWindowHandle)

    /// Applies a new frame to the window in one step, used by the default 调整窗口尺寸 hotkey
    /// (#12) to jump between preset sizes without an interactive drag/resize.
    func setWindowFrame(_ frame: WindowFrame, in window: WidgetWindowHandle)

    /// Whether the process currently holds Accessibility permission — required for
    /// `forwardKeystroke` to have any effect (ADR-0003). Checked before every forwarding attempt
    /// so a later revocation (the user turning it off in System Settings) is caught immediately,
    /// not just once at launch.
    func isAccessibilityTrusted() -> Bool

    /// Prompts the user, via the system's own Accessibility permission dialog, to grant Mochi
    /// Accessibility access — the one-time onboarding step ADR-0003 requires for
    /// `forwardKeystroke` to work. Callers are responsible for only invoking this once per app
    /// run (see `HotkeyForwarder`) since the system dialog itself has no such throttling.
    func requestAccessibilityPermission()

    /// Injects `keystroke` into the widget's own page via `CGEventPostToPid`, targeted at this
    /// process's own PID so the OS delivers a real, `isTrusted: true` key event without stealing
    /// focus from whatever app the user is actually looking at (ADR-0003). Callers are expected
    /// to only invoke this once `isAccessibilityTrusted()` is `true`.
    func forwardKeystroke(_ keystroke: Hotkey)
}
