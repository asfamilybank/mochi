import Foundation

public protocol WidgetWindowHandle {}

/// What a tray menu entry draws in its icon column (#63). Named cases rather than an `NSImage`
/// so `MochiCore`'s logic stays testable without AppKit, and so the AppKit layer is the one place
/// that knows how each is rendered.
public enum TrayMenuIcon: Equatable {
    /// An SF Symbol by name (ADR-0013) — one of `DesignTokens.Symbol`'s tray names.
    case symbol(String)
    /// The hand-drawn ghost — SF Symbols has none — at menu-item size, the same `GhostGlyph`
    /// the toolbar's Ghost Mode button wears, rendered through `SymbolMetrics`.
    case ghost
    /// The system's own Quit icon, the one the App menu's 退出 shows. It is not a public SF
    /// Symbol: AppKit draws it only for an item whose action is the standard `terminate:`, so the
    /// AppKit layer routes an item wearing this icon through that selector — which is exactly
    /// what `PlatformOps.terminateApp()` does anyway.
    case appQuit
}

/// One entry in the tray (menu-bar) icon's menu (#9, reshaped by #63) — or a separator.
///
/// Every closure is evaluated each time the menu opens, never once when the tray is built: the
/// tray is built exactly once, in `Orchestrator.start()`, and a checkmark, a greyed-out state
/// or a hotkey hint captured then would go stale on the first mode change or rebind.
///
/// `hotkeyHint` is display only: the platform shows the combo in the menu's key-equivalent
/// column, but it must never become a live key equivalent — the global hotkeys already fire
/// through Carbon, and a second path would run the action twice.
///
/// Not `Equatable` since the members are closures; tests compare `title`/`icon`/`isSeparator` and
/// call the closures directly to observe their effect.
public struct TrayMenuItem {
    public let title: String
    public let icon: TrayMenuIcon?
    public let isSeparator: Bool
    public let hotkeyHint: () -> Hotkey?
    public let isChecked: () -> Bool
    public let isEnabled: () -> Bool
    /// Whether the entry is in the menu this time it opens (#103) — for one that only belongs
    /// there while something is wrong.
    public let isVisible: () -> Bool
    public let action: () -> Void

    public init(
        title: String,
        icon: TrayMenuIcon? = nil,
        hotkeyHint: @escaping () -> Hotkey? = { nil },
        isChecked: @escaping () -> Bool = { false },
        isEnabled: @escaping () -> Bool = { true },
        isVisible: @escaping () -> Bool = { true },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSeparator = false
        self.hotkeyHint = hotkeyHint
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.action = action
    }

    private init(separator: Void) {
        title = ""
        icon = nil
        isSeparator = true
        hotkeyHint = { nil }
        isChecked = { false }
        isEnabled = { false }
        isVisible = { true }
        action = {}
    }

    /// A separator line between groups.
    public static let separator = TrayMenuItem(separator: ())
}

/// Where the widget's page stands in its history and loading (#57) — the *effective* answers, the
/// same ones the Normal Mode toolbar's back/forward segments show: back and forward include
/// `EmptyPageHistory`'s steps onto and off the Empty Page, not just the web view's own list.
/// Where the address bar's suggestions come from (#122): candidates for the words typed, and
/// the icon behind a candidate's `faviconID`.
public struct AddressSuggestionSource {
    public let candidates: ([String]) -> [AddressSuggestionCandidate]
    public let favicon: (String) -> Data?

    public init(
        candidates: @escaping ([String]) -> [AddressSuggestionCandidate], favicon: @escaping (String) -> Data?
    ) {
        self.candidates = candidates
        self.favicon = favicon
    }
}

/// How the bookmark editor (#121) was left.
public enum BookmarkEditorAnswer: Equatable, Sendable {
    /// 完成, Return, or a click outside: keep the bookmark under `name`.
    case done(name: String)
    /// Esc: keep the bookmark as it was before the editor opened.
    case cancel
    /// 移除: the page is no longer a bookmark.
    case remove
}

public struct NavigationState: Equatable {
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool

    public init(canGoBack: Bool = false, canGoForward: Bool = false, isLoading: Bool = false) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
}

public protocol PlatformOps: AnyObject {
    /// `autoplayPolicy` (#70) is baked into the web view's configuration here — WebKit only
    /// reads it at creation, which is why changing it means reopening the widget.
    func createWidgetWindow(initialFrame: WindowFrame, autoplayPolicy: WidgetConfig.AutoplayPolicy) -> WidgetWindowHandle
    func loadURL(_ url: URL, in window: WidgetWindowHandle)

    /// Shows the Empty Page's native content (#16) in place of the page area — the
    /// no-startup-target-and-no-history fallback, and the explicit "空页面" startup choice.
    /// Callers switch back to a real page by calling `loadURL`, which is responsible for hiding
    /// this content again.
    func showEmptyPageContent(in window: WidgetWindowHandle)

    /// Fronts the window *and* activates the app — used at launch and, per ADR-0012, on the one
    /// other occasion the widget is allowed to take focus: leaving Ghost Mode.
    func showWindow(_ window: WidgetWindowHandle)
    func applyZoom(_ zoom: Double, in window: WidgetWindowHandle)
    func captureWindowState(of window: WidgetWindowHandle) -> WindowState
    func onWindowWillClose(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Really closes the widget (#42): destroys the window *and* its web content so the page stops
    /// running — closing is closing, not Ghost Mode's Hidden (which keeps the page alive). Must
    /// route through the same close path the window's red button takes, so `onWindowWillClose`'s
    /// handler fires exactly once for either entry and "persist geometry before closing" has a
    /// single implementation. Implementations must not fire the handler themselves in addition.
    func closeWidgetWindow(_ window: WidgetWindowHandle)

    /// Registers the handler for the user asking the app to re-present itself with no widget
    /// window to hand — clicking the Dock icon while the widget is closed (#42). App-global, not
    /// per-window (there is no window at that point), same shape as `createTrayIcon`.
    func onReopenRequested(perform handler: @escaping () -> Void)

    /// The visible frame of every connected screen. Index 0 is always the primary
    /// (menu-bar) screen — matches `NSScreen.screens`' documented ordering.
    func visibleScreens() -> [CGRect]

    func setToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the user manually navigates via the toolbar's
    /// address bar (as opposed to a programmatic `loadURL` call).
    func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void)

    /// Applies an always-on-top window level. Driven exclusively by `GhostModeController`
    /// (ADR-0012): Ghost Mode always floats, Normal Mode is a plain window at the normal level.
    /// There is no user-facing Pin control to reflect back, so nothing else calls this and there
    /// is nothing to persist.
    func setPinned(_ pinned: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the toolbar's Ghost Mode entry button (#44) is clicked.
    /// A one-way "enter" affordance, not a toggle the button tracks state for itself — the
    /// handler routes back to the same `GhostModeController` entry point the default hotkey and
    /// tray icon already call, since this view has no self-held notion of "is Ghost Mode
    /// currently active" to reflect.
    func onGhostModeToggleRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Hands focus back to whatever app was active before Mochi, taking the menu bar with it — a
    /// no-op when Mochi isn't active. `GhostModeController` calls it on entering Ghost Mode or
    /// Hidden from any path (hotkey, tray, toolbar button), unless `isAnotherWindowKey` says
    /// focus is on a window other than the widget.
    func deactivateApp()

    /// Whether one of Mochi's windows other than `window` — the settings window, the About panel,
    /// a Popup Window — is the key window. Those are ordinary windows, so going into Ghost Mode
    /// or Hidden leaves their focus alone.
    func isAnotherWindowKey(than window: WidgetWindowHandle) -> Bool

    /// Makes Mochi the active app *without* fronting or keying the widget — for a panel that has
    /// just been put up (the About panel, #62) and must not sit behind whatever app was frontmost.
    /// Callers order the panel front first: activation then lands on the panel as key window, so
    /// a Ghost Mode widget (never key, ADR-0012) is not picked instead.
    func activateApp()

    /// Evaluates `source` in the page's JavaScript context. Callers are expected to only call
    /// this once a page has finished loading (see `onNavigationFinished`).
    func injectScript(_ source: String, in window: WidgetWindowHandle)

    /// Registers a handler invoked every time a page load finishes, so scripts can be
    /// (re-)injected after each navigation, not just the first.
    func onNavigationFinished(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// Registers a handler invoked whenever a navigation fails for a reason other than the user
    /// cancelling it themselves (changing the address mid-load, clicking a new link) — the
    /// passed string is already a user-facing description of the failure, ready to display as-is.
    func onNavigationFailed(_ window: WidgetWindowHandle, perform handler: @escaping (String) -> Void)

    /// Shows an error page in place of the loaded page (#38) — `message` is the description to
    /// display, alongside the URL that failed. Mirrors `showEmptyPageContent`'s "shared
    /// container, `isHidden` toggle" structure; hidden again once the page next finishes loading
    /// successfully.
    func showErrorPageContent(message: String, in window: WidgetWindowHandle)

    /// Registers a handler invoked whenever the loaded page's title changes (`WKWebView.title`
    /// KVO), `nil` while no page has reported one yet. Drives the window's dynamic title (#18,
    /// `AddressBarController`) independently of the Normal Mode toolbar's own Smart Address Field
    /// display, which reads the same underlying signal directly inside the AppKit view.
    func onPageTitleChanged(_ window: WidgetWindowHandle, perform handler: @escaping (String?) -> Void)

    /// Registers a handler invoked whenever the widget's *main page* moves to a new address
    /// (#102, 历史记录): a new document committing, and a same-document change such as
    /// `pushState` (a video site switching videos) once the page has finished loading. Never for
    /// an iframe, a redirect hop that doesn't commit, or a Popup Window — those have no handler.
    /// A fragment-only change isn't reported either: it is still the same page.
    func onMainFrameURLChanged(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void)

    /// Registers a handler invoked whenever the widget's page gets its site icon — the one the
    /// address bar shows, fetched once a page has finished loading (#117, 历史记录): the page it
    /// was fetched for, and the icon as a `FaviconLoader.historyPixelSize`-square PNG. An icon that
    /// arrives once the page has moved to another origin is never reported. Never for a Popup
    /// Window.
    func onSiteIconLoaded(_ window: WidgetWindowHandle, perform handler: @escaping (URL, Data) -> Void)

    /// Registers a handler invoked whenever the Empty Page (#16) is shown or hidden — including
    /// by back/forward, which the view handles on its own (`EmptyPageHistory`) without a core
    /// round trip. The window title (`AddressBarController`) needs it: while the Empty Page is
    /// up, the title of the page that was left behind no longer describes the window.
    func onEmptyPageVisibilityChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void)

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

    /// Sets the window's overall content opacity — the single outlet for how visible the widget
    /// is (ADR-0012), covering both Ghost Mode's configured target and fully invisible (`0`).
    /// Implemented via `NSWindow.alphaValue` plus the WKWebView `drawsBackground` private-API hack
    /// (ADR-0001) needed to let anything below alpha 1.0 show through at all.
    ///
    /// `0` must stay an alpha value rather than becoming an `orderOut`: a window ordered out is
    /// judged occluded by WebKit, which throttles its timers and can stall video — and "the page
    /// keeps running while hidden" is the whole point of the boss key.
    func setContentOpacity(_ opacity: Double, in window: WidgetWindowHandle)

    /// Enables/disables `NSWindow.ignoresMouseEvents` — Ghost Mode's click-through behavior.
    func setMousePassthrough(_ enabled: Bool, in window: WidgetWindowHandle)

    /// Registers a system-wide hotkey and returns whether registration succeeded (`false` when
    /// another application already holds that combination) — callers must surface failure to the
    /// user rather than silently dropping it.
    @discardableResult
    func registerGlobalHotkey(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool

    /// Hands `hotkey` back to the system so another app (or a later re-registration of the same
    /// combo, e.g. after the user edits a mapping) can claim it. A safe no-op when `hotkey` isn't
    /// currently registered.
    func unregisterGlobalHotkey(_ hotkey: Hotkey)

    /// Surfaces a user-facing alert — used for conditions like a hotkey conflict that must not
    /// fail silently.
    func presentAlert(title: String, message: String)

    /// Turns magnetic edge/corner snapping (#6) on or off for interactive drags. The distance it
    /// snaps from is a `WindowSnapping` constant, not a setting — a knob whose effect nobody can
    /// judge is worse than no knob (ADR-0012). Snapping is inherently Normal-Mode-only: it acts
    /// during a manual drag, and a Ghost Mode window is click-through and usually invisible.
    /// 字体大小不得小于 (#70): `nil` removes the limit. Applies to the live page immediately.
    func setMinimumFontSize(_ size: Int?, in window: WidgetWindowHandle)

    func setSnapEnabled(_ enabled: Bool, in window: WidgetWindowHandle)

    /// The Empty Page's hotkey quick reference (#83), as computed from the config in effect.
    /// Pushed on open and on every `reapplyConfiguration()`; the Empty Page only draws it.
    func setHotkeyQuickReference(_ entries: [HotkeyQuickReferenceEntry], in window: WidgetWindowHandle)

    /// 显示网页开发者功能 (#72): whether the page offers 检查元素 in its context menu
    /// (`WKWebView.isInspectable`). Pushed on open and on every `reapplyConfiguration()`.
    func setWebInspectable(_ enabled: Bool, in window: WidgetWindowHandle)

    /// 通过 HTTP 连接网站前接收警告 (#72): when on, a navigation that can't be upgraded to HTTPS
    /// shows WebKit's warning and continues only after the user confirms
    /// (`.userMediatedFallbackToHTTP`); when off, requests go out as typed (`.keepAsRequested`). The
    /// platform consults the pushed value in every navigation policy decision.
    func setHTTPWarningEnabled(_ enabled: Bool, in window: WidgetWindowHandle)

    /// 清除浏览数据… (#107): removes the website data of `types` that was modified at or after
    /// `modifiedSince` (`.distantPast` for 时间不限), from every website — and, with the cache,
    /// Mochi's favicon cache. App-global: not tied to a window, and works with the widget closed.
    /// Never touches `config.toml` and never reloads a page. Confirmation is the caller's job.
    func removeData(ofTypes types: Set<WebsiteDataCategory>, modifiedSince: Date)

    /// 管理网站和数据… (#106): every website data record WebKit holds, one per registrable domain.
    /// App-global, like `removeData(ofTypes:modifiedSince:)`. `completion` runs on the main thread.
    func fetchWebsiteDataRecords(completion: @escaping ([WebsiteDataRecord]) -> Void)

    /// Removes the `kinds` of data held by the records named `names` — whole records are WebKit's
    /// unit, so a host's data goes with its domain's. Never touches `config.toml` (网页权限
    /// exceptions are reset separately), and never reloads the page. `completion` runs on the
    /// main thread once WebKit is done.
    func removeWebsiteData(
        ofKinds kinds: Set<WebsiteDataKind>, forRecordsNamed names: [String], completion: @escaping () -> Void)

    /// Creates the app's persistent menu-bar (tray) icon (#9) — present for the app's entire
    /// lifetime regardless of Normal/Ghost Mode — populated with `items` in order. Not tied to a
    /// `WidgetWindowHandle` since the tray icon is app-global, not per-window. Called once, at
    /// launch — so the items' closures (checked, enabled, hotkey hint) must be re-evaluated by
    /// the platform every time the menu opens (#63).
    func createTrayIcon(items: [TrayMenuItem])

    /// Terminates the app — the tray icon's "Quit" entry (#9) must work on its own, since Ghost
    /// Mode can leave every window fully hidden with no other way to reach a quit control.
    func terminateApp()

    /// Reloads the widget's currently-loaded page — the default 刷新页面 hotkey's (#12) action.
    func reloadPage(in window: WidgetWindowHandle)

    /// Stops the widget's in-flight page load (#60) — the Display menu's 停止 (⌘.). The address
    /// bar's embedded stop icon calls the same AppKit path directly.
    func stopLoading(in window: WidgetWindowHandle)

    /// The page's current back/forward/loading state (#57), read on demand — the answers the
    /// toolbar's own back/forward segments are enabled by, so the main menu can never disagree
    /// with them. Loading is reported as `false` while the Empty Page is up: nothing the user can
    /// see is loading then.
    func navigationState(of window: WidgetWindowHandle) -> NavigationState

    /// Goes back / forward one step (#59) — exactly what the toolbar's back/forward segments do,
    /// Empty Page steps included (the oldest page's back lands on the Empty Page, and forward from
    /// there returns to it). A no-op when `navigationState(of:)` says that direction is closed.
    func goBack(in window: WidgetWindowHandle)
    func goForward(in window: WidgetWindowHandle)
    /// Puts the address bar into editing with its whole address selected (#61, 打开位置… ⌘L) —
    /// the same path a click on the bar takes, so it works on the Empty Page too.
    func focusAddressBar(in window: WidgetWindowHandle)
    /// Where the address bar's suggestions come from (#122, ADR-0034), handed over once per
    /// widget. The bar asks it on every keystroke; it reads the history at that moment.
    func setAddressSuggestionSource(_ source: AddressSuggestionSource, in window: WidgetWindowHandle)
    /// The bookmark editor (#121, ADR-0033): a popover under the address bar holding the
    /// bookmark's `name` for editing, with 完成 and 移除. The bookmark already exists when it opens
    /// — ⌘D has added it — so `answer` is told what to make of it, exactly once.
    func presentBookmarkEditor(
        name: String, in window: WidgetWindowHandle, answer: @escaping (BookmarkEditorAnswer) -> Void)

    // MARK: 系统权限 (#98, ADR-0026) — one set of calls for every `SystemPermission`.

    /// Where `permission` stands right now — read fresh at every use, since the user changes it in
    /// System Settings, behind Mochi's back. Accessibility also reads `.authorized` while
    /// Accessibility is granted (ADR-0029); the Downloads folder always reads `.unqueryable`.
    func systemPermissionStatus(_ permission: SystemPermission) -> SystemPermissionStatus

    /// Asks the system for `permission`: for Accessibility the system's own dialog pointing at
    /// System Settings, for the camera and microphone the system's access request — each followed
    /// by `onSystemPermissionsMayHaveChanged`. The system itself never stops a dialog from coming
    /// back, so how often to ask is the caller's to decide (see `VideoControl`). A no-op for the Downloads folder, which has no request of its own.
    func requestSystemPermission(_ permission: SystemPermission)

    /// Opens System Settings at `permission`'s page in 隐私与安全性 (the Downloads folder's is
    /// 文件和文件夹).
    func openSystemSettings(for permission: SystemPermission)

    /// Reads / writes a flag kept across launches in `UserDefaults` (see `SystemPermissionMarker`).
    func isSystemPermissionMarkerSet(_ marker: SystemPermissionMarker) -> Bool
    func setSystemPermissionMarker(_ marker: SystemPermissionMarker, _ isSet: Bool)

    /// Adds a handler run whenever a `SystemPermission` may have changed: when Mochi comes back to
    /// the front (System Settings sends no notice of its own) and when a request is answered.
    /// Consumers just read the statuses again. Every call adds one more handler, for as long as
    /// the app runs — app-global, like the consumers that register them.
    /// #105: also when `SystemPermissionMarker.downloadsFolderWriteDenied` changes value — that
    /// marker is all there is to know about the Downloads folder's permission.
    func onSystemPermissionsMayHaveChanged(perform handler: @escaping () -> Void)

    /// Hands `keystroke` to `window`'s web view as a real key event (#93, ADR-0025): the page sees
    /// an `isTrusted: true` keydown/keyup at whatever element has focus inside it, iframes
    /// included, while the window stays non-key and Mochi stays in the background — Ghost Mode's
    /// never-focus rule holds. Needs no 系统权限. Whatever the page leaves
    /// unhandled goes no further: no menu key equivalent, no 视频控制 listener ever sees it.
    func forwardKeystroke(_ keystroke: Hotkey, in window: WidgetWindowHandle)

    // MARK: 网页交互请求 (#66) — see `WebInteractionRequests.swift` for the seam's shape. Each kind
    // gets its own hook; the handler's return value is the decision the platform must execute.

    /// Registers the handler that decides how a page's `alert`/`confirm`/`prompt` is settled.
    /// The platform presents a sheet on `.presentSheet` and settles silently otherwise; either
    /// way it must complete WebKit's callback exactly once.
    func onJavaScriptDialogRequested(
        _ window: WidgetWindowHandle, perform handler: @escaping (JavaScriptDialogRequest) -> JavaScriptDialogDecision)

    /// Registers the handler that decides how a page's file-upload request is settled.
    func onFileUploadRequested(_ window: WidgetWindowHandle, perform handler: @escaping (FileUploadRequest) -> FileUploadDecision)

    /// Registers the handler that decides where a page's download lands (#68). The platform turns
    /// unshowable responses and `download`-attribute links into downloads, asks this handler for
    /// the destination, executes it (a Save panel sheet only on `.askWithSavePanel`), and bounces
    /// the Dock's Downloads stack when the file is complete. The handler answers through its
    /// completion (on the main thread), possibly later: deciding may wait on disk access (#99).
    func onDownloadRequested(
        _ window: WidgetWindowHandle,
        perform handler: @escaping (DownloadRequest, @escaping (DownloadDestinationDecision) -> Void) -> Void)

    /// #105: registers the handler told how each download ended — finished or failed, once it had
    /// a destination (`DownloadWriteResult.classifying` sorts the failure). The platform shows
    /// 「无法存到下载文件夹」 as a sheet on `.offerAnotherLocation` and reports the answer through
    /// `onDownloadsFolderDeniedAnswered`, keeping the download's original request for a retry.
    func onDownloadEnded(_ window: WidgetWindowHandle, perform handler: @escaping (DownloadOutcome) -> DownloadOutcomeDecision)

    /// #105: registers the handler that decides what follows the user's answer to
    /// 「无法存到下载文件夹」. On `.saveElsewhereWithSavePanel` the platform shows a Save panel and
    /// starts that download's original request again, landing where the panel says.
    func onDownloadsFolderDeniedAnswered(
        _ window: WidgetWindowHandle,
        perform handler: @escaping (DownloadsFolderDeniedAnswer) -> DownloadsFolderDeniedFollowUp)

    /// Registers the handler that decides a page's camera/microphone request (#69) — from the
    /// widget's page or any of its Popup Windows (`MediaCaptureRequest.source`). The platform
    /// answers `.grant`/`.deny` directly; on `.ask` (#101) it shows `MediaCapturePrompt` as a sheet
    /// on the requesting window and holds WebKit's decision until the user answers.
    func onMediaCaptureRequested(
        _ window: WidgetWindowHandle, perform handler: @escaping (MediaCaptureRequest) -> MediaCaptureDecision)

    /// #101: registers the handler told the user's answer to a `.ask` prompt; it returns whether
    /// to grant. A sheet ended without an answer (the window closing) denies without calling it.
    func onMediaCapturePromptAnswered(
        _ window: WidgetWindowHandle, perform handler: @escaping (MediaCaptureRequest, MediaCapturePromptAnswer) -> Bool)

    /// #101: registers the handler told that one of the widget's web views committed a new
    /// document in its main frame — a navigation or a reload, but not a same-document change
    /// (`pushState`, a fragment), which keeps the page load. Ends that web view's 「仅这次允许」.
    func onNewDocumentCommitted(_ window: WidgetWindowHandle, perform handler: @escaping (WebViewSource) -> Void)

    /// #96: WebKit remembers a camera/microphone grant on its own and stops asking
    /// `onMediaCaptureRequested` while the page stays on the same website — through `pushState`,
    /// same-origin navigations, even the page reloading itself — until the app loads or reloads
    /// the web view, or the page moves to another website. (A denial isn't remembered.) Makes it
    /// forget, so the next request is decided again. Forgetting also stops a capture in progress;
    /// `onlyIfIdle` leaves the web view alone while it is capturing.
    func forgetMediaCaptureGrants(in window: WidgetWindowHandle, of source: WebViewSource, onlyIfIdle: Bool)

    // #67: new windows and Popup Windows

    /// Registers the handler that decides a page's new-window request — from the widget's page or
    /// from any of its Popup Windows (`NewWindowRequest.opener` says which). The platform asks for
    /// every `target=_blank` link, every ⌘-clicked link and every `window.open` that reaches
    /// WebKit's new-window delegate, then executes the answer; with no handler it opens nothing.
    func onNewWindowRequested(_ window: WidgetWindowHandle, perform handler: @escaping (NewWindowRequest) -> NewWindowDecision)

    /// Hands `url` to the user's default browser (⌘-click on a link). App-global.
    func openInDefaultBrowser(_ url: URL)

    /// Closes every Popup Window the widget opened — called from the widget's single teardown
    /// point, so no popup outlives its widget. A no-op when there are none.
    func closePopupWindows(of window: WidgetWindowHandle)

    /// 弹出式窗口 (#67): `WKPreferences.javaScriptCanOpenWindowsAutomatically` on the widget's web
    /// view — `false` (阻止) lets WebKit itself drop a `window.open` with no user gesture. Pushed on
    /// open and on every `reapplyConfiguration()`; WebKit honours the change on the live page.
    func setPopupWindowsAllowed(_ allowed: Bool, in window: WidgetWindowHandle)

    // MARK: 视频控制 (#74, ADR-0020)

    /// Starts reporting raw keyboard and mouse input to `handler` — from every app, and from
    /// Mochi's own windows too — strictly listen-only: no event is ever consumed or altered, so
    /// every app still gets every key exactly as if Mochi weren't running. Other apps' combos
    /// with neither ⌃ nor ⌘ (⌥P) arrive only with Accessibility (ADR-0029); modifier changes
    /// and ⌃/⌘ combos arrive without it, as does all of Mochi's own input. App-global; a second
    /// start without a stop in between is a caller bug.
    func startObservingInput(perform handler: @escaping (RawInputEvent) -> Void)

    /// Stops what `startObservingInput` started. A no-op when not observing.
    func stopObservingInput()

    /// Runs `work` on the main thread after `delay` seconds, unless the returned closure is
    /// called first — how a tap held back for a possible double tap is let go (#91).
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void

    /// Carries `command` out on the page's target video — choosing it (playing, else most
    /// recently played, else largest visible) and doing nothing when the page has none.
    func performVideoCommand(_ command: VideoCommand, in window: WidgetWindowHandle)

    /// Pauses every `<video>`/`<audio>` that is playing, in every frame of the page — cross-origin
    /// iframes included (#76). Never resumes anything; there is no inverse.
    func pauseAllMedia(in window: WidgetWindowHandle)
}

// #70
extension PlatformOps {
    /// Convenience for callers that don't care about autoplay (tests, mostly).
    func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle {
        createWidgetWindow(initialFrame: initialFrame, autoplayPolicy: .allowAll)
    }
}
