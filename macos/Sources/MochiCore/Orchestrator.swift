import Foundation

/// A main-menu command that acts on the widget (#57) — what `Orchestrator.canPerform(_:)` and
/// `perform(_:)` take, so every widget-bound menu item is gated by one set of rules instead of
/// each menu item carrying its own.
public enum WidgetCommand: CaseIterable, Sendable {
    /// 显示 → 重新载入页面 (⌘R). Offered mid-load too — reloading is how you retry a stuck page.
    case reload
    /// 显示 → 停止 (⌘., #60). Only while the page is loading.
    case stop
    /// 显示 → 放大 (⌘+).
    case zoomIn
    /// 显示 → 缩小 (⌘-).
    case zoomOut
    /// 显示 → 实际大小 (⌘0).
    case resetZoom
    /// 历史记录 → 返回 (⌘[) (#59).
    case goBack
    /// 历史记录 → 前进 (⌘]) (#59).
    case goForward
    /// 文件 → 打开位置… (⌘L, #61) — the one command that is offered *without* a widget: it
    /// reopens one first, then focuses its address bar.
    case openLocation
}

public final class Orchestrator {
    /// The step `zoomIn`/`zoomOut` (#37) move by on each call, and the range they clamp to —
    /// matching a typical browser's zoom-shortcut feel rather than a jump straight to the extreme.
    private static let zoomStep = 0.1
    private static let zoomRange = 0.25...5.0

    private let platformOps: PlatformOps
    private let currentConfig: () -> WidgetConfig
    private let persistWindowState: (WindowState) -> Void
    private let persistURL: (URL) -> Void
    /// #101: the transform-based write `SettingsController` also gets — 网页权限 exceptions
    /// remembered from Mochi's prompt are applied on top of whatever was persisted last.
    private let persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void
    private let openSettings: () -> Void
    private let openAbout: () -> Void
    /// #102: `nil` keeps no history at all (most tests).
    private let historyStore: HistoryStore?
    private var window: WidgetWindowHandle?
    private var ghostModeController: GhostModeController?
    private var addressBarController: AddressBarController?
    private var hotkeyForwarder: HotkeyForwarder?
    private var videoControl: VideoControl?
    private var currentZoom: Double = 1.0

    /// Whether a widget window currently exists (#42). The main menu asks `canPerform(_:)`
    /// instead, which also rules out Ghost Mode.
    public var hasActiveWidget: Bool { window != nil }

    /// - Parameter currentConfig: read at every point of use — the resolved startup content on
    ///   each `openWidget()`, the scripts injected after each navigation, the combo each global
    ///   hotkey press means right now — never captured once at launch (#46's "read, don't cache"
    ///   rule, and what lets `openWidget()` honour a URL persisted mid-session).
    public init(
        platformOps: PlatformOps,
        currentConfig: @escaping () -> WidgetConfig,
        persistWindowState: @escaping (WindowState) -> Void = { _ in },
        persistURL: @escaping (URL) -> Void = { _ in },
        persist: @escaping (@escaping (WidgetConfig) -> WidgetConfig) -> Void = { _ in },
        openSettings: @escaping () -> Void = {},
        openAbout: @escaping () -> Void = {},
        historyStore: HistoryStore? = nil
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.persistWindowState = persistWindowState
        self.persistURL = persistURL
        self.persist = persist
        self.openSettings = openSettings
        self.openAbout = openAbout
        self.historyStore = historyStore
    }

    /// Launch. Everything app-global — and therefore done exactly once, never again on a reopen
    /// (#42) — lives here: the tray icon (`NSStatusItem` is app-global; a second call would grow a
    /// second icon), the global hotkey registrations (Carbon hotkeys don't come and go with the
    /// widget window), and the Dock-reopen hook. The widget itself goes through `openWidget()`,
    /// the same operation a later reopen calls, so launch and reopen cannot drift apart.
    public func start() {
        hotkeyForwarder = HotkeyForwarder(
            platformOps: platformOps,
            isGhostModeActive: { [weak self] in self?.isGhostModeActive ?? false },
            currentWindow: { [weak self] in self?.window }
        )
        videoControl = VideoControl(
            platformOps: platformOps,
            currentConfig: currentConfig,
            isGhostModeActive: { [weak self] in self?.isGhostModeActive ?? false },
            currentWindow: { [weak self] in self?.window },
            forward: { [weak self] in self?.hotkeyForwarder?.forward($0) }
        )
        registerGlobalHotkeys()
        platformOps.createTrayIcon(items: trayMenuItems())
        platformOps.onReopenRequested { [weak self] in
            self?.openWidget()
        }
        // #110: what expired while Mochi wasn't running.
        removeExpiredHistory()
        openWidget()
    }

    /// The tray menu (#63), grouped after Bob: the widget's three states, then the app's own
    /// panels, then quit. Built once by `start()`, so every checkmark, greyed-out state and hint
    /// is a closure the platform re-evaluates each time the menu opens — the hints read the
    /// *configured* combo live, so a rebind shows on the next open, and a combo that failed to
    /// register is still shown (it is what the user asked for, and the settings panel says so).
    /// Hotkey Forwarding mappings are not listed; they are page keystrokes, not Mochi commands.
    private func trayMenuItems() -> [TrayMenuItem] {
        [
            // First, because while the widget is closed this is the one way back that's always
            // on screen (#42). Never greyed out: with a widget open it brings it forward instead.
            TrayMenuItem(title: "打开窗口", icon: .symbol(DesignTokens.Symbol.openWidget)) { [weak self] in
                self?.openWidget()
            },
            // The same `perform` the global hotkey dispatches to, so entering Ghost Mode from the
            // tray is indistinguishable from the hotkey (#44). From Ghost Mode — fully Hidden and
            // click-through included — a toggle is a plain exit: the tray is the one control that
            // always reaches the user, so it must always be able to bring the widget back.
            TrayMenuItem(
                title: "幽灵模式", icon: .ghost,
                hotkeyHint: { [weak self] in self?.currentConfig().hotkey(for: .toggleGhostMode) },
                isChecked: { [weak self] in self?.ghostModeController?.mode == .ghost },
                isEnabled: { [weak self] in self?.window != nil }
            ) { [weak self] in
                self?.perform(HotkeyAction.toggleGhostMode)
            },
            // Shown but greyed out in Normal Mode, where Hidden has no meaning (ADR-0012) — the
            // same no-op the hotkey is there, made visible rather than silent.
            TrayMenuItem(
                title: "隐藏窗口", icon: .symbol(DesignTokens.Symbol.hideWidget),
                hotkeyHint: { [weak self] in self?.currentConfig().hotkey(for: .hideWidget) },
                isChecked: { [weak self] in self?.ghostModeController?.isHidden ?? false },
                isEnabled: { [weak self] in self?.ghostModeController?.mode == .ghost }
            ) { [weak self] in
                self?.perform(HotkeyAction.hideWidget)
            },
            .separator,
            // Only while Accessibility is missing and a 视频控制 key needs it (#111, ADR-0029):
            // in Ghost Mode the tray is the one place left to say why that key does nothing. Its
            // click does what the settings panel's button would — ask while Mochi never has,
            // System Settings once it has.
            TrayMenuItem(
                title: "视频控制需要辅助功能权限…", icon: .symbol(DesignTokens.Symbol.systemPermissionMissing),
                isVisible: { [weak self] in self?.trayPrompt(for: .accessibility) != nil }
            ) { [weak self] in
                guard let self else { return }
                trayPrompt(for: .accessibility)?.perform(on: platformOps)
            },
            TrayMenuItem(
                title: "设置…", icon: .symbol(DesignTokens.Symbol.settings),
                hotkeyHint: { DefaultHotkeys.openSettings }, action: openSettings),
            // The App menu's About (#62): the panel becomes key, the widget is left alone.
            TrayMenuItem(title: "关于 \(AppInfo.name)", icon: .symbol(DesignTokens.Symbol.about)) { [weak self] in
                self?.openAboutPanel()
            },
            .separator,
            TrayMenuItem(
                title: "退出", icon: .appQuit,
                hotkeyHint: { DefaultHotkeys.quit }, action: platformOps.terminateApp),
        ]
    }

    /// The tray's prompt for `permission`, if one belongs there right now (#103) — read from the
    /// live config and the system's live answer each time the menu opens, with Mochi's own record
    /// of having asked for Accessibility, which the system can't tell apart from a refusal (#111).
    private func trayPrompt(for permission: SystemPermission) -> SystemPermissionPrompt? {
        SystemPermissionPrompts.prompts(
            for: currentConfig(), status: platformOps.systemPermissionStatus,
            accessibilityRequested: platformOps.isSystemPermissionMarkerSet(.accessibilityRequested)
        )
        .first { $0.permission == permission && $0.placement == .trayMenu }
    }

    /// Opens the widget window (#42) — at launch and again after a `⌘W`/red-button close. A
    /// reopen is defined as a fresh launch: startup content is re-resolved from the *current*
    /// config (so a fixed startup URL wins over whatever was being viewed at close), the page is
    /// loaded from scratch, and a brand-new `GhostModeController` means the widget is back in
    /// Normal Mode; only window geometry and zoom carry over, via the persisted `windowState`.
    ///
    /// Idempotent while a widget already exists: the tray's 打开窗口 entry then just brings it
    /// forward. If that widget is sitting in Ghost Mode this leaves Ghost Mode rather than fronting
    /// a click-through window — "bring it back so I can use it" is the only reading of the request
    /// that doesn't hand focus to a window ADR-0012 says may never be key.
    public func openWidget() {
        openWidget(startingAt: nil)
    }

    /// `openWidget()`, except that a widget created here loads `url` in place of the startup
    /// content — for opening from history (#108), where loading the startup page first would
    /// flash it and record a visit nobody made. Everything else about the reopen is the same.
    private func openWidget(startingAt url: URL?) {
        if let window {
            if let ghostModeController, ghostModeController.mode == .ghost {
                ghostModeController.exitGhostMode()
            } else {
                platformOps.showWindow(window)
            }
            return
        }

        let config = currentConfig()
        let screens = platformOps.visibleScreens()
        let frame = WindowPlacement.resolve(persisted: config.windowState?.frame, visibleScreens: screens)
        let window = platformOps.createWidgetWindow(initialFrame: frame, autoplayPolicy: config.autoplayPolicy)
        self.window = window
        self.currentZoom = config.windowState?.zoom ?? 1.0

        let addressBarController = AddressBarController(platformOps: platformOps, window: window)
        self.addressBarController = addressBarController

        // On screen before anything loads. WebKit treats a web view in a window that was never
        // ordered front as not visible and skips building its rendering layers, and nothing later
        // asks it to reconsider — so a page that finished loading during that window came up blank
        // and stayed blank until a scroll forced a repaint. A slow page hid this by not finishing
        // until after the window was already up.
        platformOps.showWindow(window)

        switch url.map(StartupContent.url) ?? StartupResolution.resolveStartupContent(for: config) {
        case .url(let url):
            platformOps.loadURL(url, in: window)
            addressBarController.urlLoaded(url)
        case .emptyPage:
            platformOps.showEmptyPageContent(in: window)
        }
        if let zoom = config.windowState?.zoom {
            platformOps.applyZoom(zoom, in: window)
        }
        platformOps.setToolbarVisible(true, in: window)
        platformOps.setSnapEnabled(config.isSnapEnabled, in: window)
        platformOps.setMinimumFontSize(config.minimumFontSize, in: window)
        platformOps.setWebInspectable(config.isWebInspectorEnabled, in: window)
        platformOps.setHTTPWarningEnabled(config.isHTTPWarningEnabled, in: window)
        platformOps.setPopupWindowsAllowed(config.popupWindowPolicy == .allow, in: window)
        platformOps.setHotkeyQuickReference(HotkeyQuickReference.entries(for: config), in: window)
        platformOps.onWindowWillClose(window) { [weak self] in
            self?.handleWindowWillClose()
        }
        platformOps.onURLSubmitted(window) { [weak self] url in
            self?.handleURLSubmitted(url)
        }
        platformOps.onNavigationFinished(window) { [weak self] in
            self?.injectConfiguredScripts()
        }
        platformOps.onNavigationFailed(window) { [weak self] message in
            self?.handleNavigationFailed(message)
        }
        registerWebInteractionRequestHandlers(for: window)
        registerHistoryRecording(for: window, addressBarController: addressBarController)

        let ghostModeController = GhostModeController(platformOps: platformOps, window: window, currentConfig: currentConfig)
        self.ghostModeController = ghostModeController
        ghostModeController.onModeChanged = { [weak self] in
            self?.videoControl?.refreshObservation()
            if self?.isGhostModeActive == true { self?.mediaCapturePermissions?.ghostModeEntered() }
        }
        // The toolbar button (#44) calls the exact same entry point as the hotkey and tray paths —
        // no shortcut path of its own; giving up focus happens inside it, on every path.
        platformOps.onGhostModeToggleRequested(window) { [weak ghostModeController] in
            ghostModeController?.toggle()
        }
    }

    /// Really closes the widget (#42). Routes through the platform's close so the window's own
    /// will-close callback (`handleWindowWillClose`) does the teardown, exactly as it does for the
    /// red close button and `⌘W`: one close path, one place that persists geometry first.
    public func closeWidget() {
        guard let window else { return }
        platformOps.closeWidgetWindow(window)
    }

    /// The settings panel's 重新打开窗口 button (#70): the full close + reopen, so the widget comes
    /// back exactly as a fresh launch would — the one way to apply settings WebKit reads only at
    /// web-view creation (autoplay). With no widget open it simply opens one.
    public func reopenWidget() {
        closeWidget()
        openWidget()
    }

    /// The single teardown point for both close entries. Persists geometry while the window still
    /// exists, then forgets every per-window object — from here on the two global hotkeys and the
    /// widget-bound menu items find no `ghostModeController`/`window` and silently do nothing, and
    /// the next `openWidget()` starts clean.
    private func handleWindowWillClose() {
        persistCurrentWindowState()
        // #67: no Popup Window outlives its widget.
        if let window { platformOps.closePopupWindows(of: window) }
        window = nil
        ghostModeController = nil
        addressBarController = nil
        mediaCapturePermissions = nil  // #101: 「仅这次允许」 ends with the widget
        videoControl?.refreshObservation()
    }

    /// Registers every global hotkey Mochi holds — the two action hotkeys at their currently
    /// configured combos (#45), then each forwarding mapping's trigger (#11) — as one batch, so
    /// registration failures (a combo another app already holds) collapse into a single alert
    /// rather than one modal per conflict. A mapping whose trigger collides with an action hotkey
    /// is skipped and counted as a conflict too: Carbon accepts the same combo twice in-process
    /// (it just fires both handlers), so this is the only place that collision can be caught.
    ///
    /// Every registration dispatches through `handleGlobalHotkeyPressed`, which resolves the combo
    /// against the config *at press time* — the same handler `SettingsController` registers when
    /// it rebinds a hotkey or edits a mapping live, so a launch-time and a runtime registration
    /// are indistinguishable.
    ///
    /// Reload/zoom are *not* in this batch — #37 downgrades them from global hotkeys to local
    /// menu shortcuts (⌘R/⌘±/⌘0), reachable only while Mochi is the key window, which needs no
    /// Carbon registration at all.
    private func registerGlobalHotkeys() {
        let config = currentConfig()
        var failedActionNames: [String] = []
        var registered: Set<Hotkey> = []
        // A cleared action (#85) holds no combo at all.
        for action in HotkeyAction.allCases {
            guard let hotkey = config.hotkey(for: action) else { continue }
            if register(hotkey) {
                registered.insert(hotkey)
            } else {
                failedActionNames.append(action.displayName)
            }
        }
        if !failedActionNames.isEmpty {
            platformOps.presentAlert(
                title: "部分热键注册失败",
                message: "以下功能的热键已被其他应用占用，请检查冲突：\(failedActionNames.joined(separator: "、"))"
            )
        }

        var mappingConflictCount = 0
        // A tap or double tap (#92) is listened for by `videoControl`, not registered.
        for hotkey in config.hotkeyMappings.compactMap(\.registeredHotkey) {
            guard !registered.contains(hotkey) else {
                mappingConflictCount += 1
                continue
            }
            if register(hotkey) {
                registered.insert(hotkey)
            } else {
                mappingConflictCount += 1
            }
        }
        if mappingConflictCount > 0 {
            platformOps.presentAlert(
                title: "部分映射注册失败",
                message: "\(mappingConflictCount) 条映射的触发键已被其他应用或 Mochi 自身的热键占用，请在设置的「热键传递」里调整。"
            )
        }
    }

    private func register(_ hotkey: Hotkey) -> Bool {
        platformOps.registerGlobalHotkey(hotkey) { [weak self] in
            self?.handleGlobalHotkeyPressed(hotkey)
        }
    }

    /// What a press of any registered global hotkey does, decided against the *current* config
    /// (#45/#46): an action hotkey toggles Ghost Mode or Hidden; a forwarding mapping's trigger
    /// forwards its page keystroke. Public because `SettingsController` registers this exact
    /// handler when it rebinds a hotkey or edits a mapping at runtime — there is no second
    /// dispatch path for hotkeys registered after launch. Resolving at press time is also what
    /// makes editing a mapping's *page keystroke* take effect with no re-registration at all.
    ///
    /// Both action hotkeys are silent no-ops while the widget is closed (#42): a hotkey must never
    /// conjure up an invisible window the user didn't know existed.
    public func handleGlobalHotkeyPressed(_ hotkey: Hotkey) {
        let config = currentConfig()
        if let action = HotkeyAction.allCases.first(where: { config.hotkey(for: $0) == hotkey }) {
            perform(action)
            return
        }
        if let mapping = config.hotkeyMappings.first(where: { $0.registeredHotkey == hotkey }) {
            hotkeyForwarder?.forward(mapping.pageKeystroke)
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleGhostMode: ghostModeController?.toggle()
        case .hideWidget: ghostModeController?.toggleHidden()
        }
    }

    /// Re-applies the settings that don't take effect by being re-read (#46): Snap has to be
    /// pushed to the live window, an opacity edit made *while in Ghost Mode* has to be pushed
    /// down right now (see `GhostModeController.reapplyConfiguration`), and 视频控制 has to start
    /// or stop listening when an edit binds its first key or clears its last one (#78), and the Empty
    /// Page's quick reference has to be redrawn with the hotkeys now in effect (#83).
    /// Everything else in the config is read at its point of use and needs no call here. `SettingsController`
    /// invokes this after every persisted edit; a no-op while the widget is closed.
    public func reapplyConfiguration() {
        guard let window else { return }
        platformOps.setSnapEnabled(currentConfig().isSnapEnabled, in: window)
        platformOps.setMinimumFontSize(currentConfig().minimumFontSize, in: window)
        platformOps.setWebInspectable(currentConfig().isWebInspectorEnabled, in: window)
        platformOps.setHTTPWarningEnabled(currentConfig().isHTTPWarningEnabled, in: window)
        platformOps.setPopupWindowsAllowed(currentConfig().popupWindowPolicy == .allow, in: window)
        platformOps.setHotkeyQuickReference(HotkeyQuickReference.entries(for: currentConfig()), in: window)
        ghostModeController?.reapplyConfiguration()
        videoControl?.refreshObservation()
    }

    private func handleURLSubmitted(_ url: URL) {
        guard let window else { return }
        platformOps.loadURL(url, in: window)
        addressBarController?.urlLoaded(url)
        persistURL(url)
    }

    /// Whether the main menu should offer `command` right now (#57) — asked every time the menu
    /// opens or a key equivalent fires. Nothing is offered without a widget to act on, and nothing
    /// in Ghost Mode either: `CONTEXT.md` has no reload, no zoom and no toolbar there, and a menu
    /// bar that becomes clickable once the user activates Mochi from the Dock mustn't reopen that
    /// door — leaving Ghost Mode comes first.
    ///
    /// The one exception is `openLocation` (#61): with no widget it is still offered, and means
    /// "reopen, then focus the address bar" — Safari's ⌘L with no window open. Ghost Mode still
    /// rules it out like everything else.
    public func canPerform(_ command: WidgetCommand) -> Bool {
        if ghostModeController?.mode == .ghost { return false }
        switch command {
        case .openLocation:
            return true
        case .goBack:
            guard let window else { return false }
            return platformOps.navigationState(of: window).canGoBack
        case .goForward:
            guard let window else { return false }
            return platformOps.navigationState(of: window).canGoForward
        case .reload, .zoomIn, .zoomOut, .resetZoom:
            return window != nil
        case .stop:
            return window.map { platformOps.navigationState(of: $0).isLoading } ?? false
        }
    }

    /// Runs `command` if `canPerform(_:)` allows it, and otherwise does nothing — so a key
    /// equivalent that reaches here without passing menu validation still obeys the same rules.
    public func perform(_ command: WidgetCommand) {
        guard canPerform(command) else { return }
        switch command {
        case .reload: reloadPage()
        case .stop: stopLoading()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .resetZoom: resetZoom()
        case .goBack: window.map(platformOps.goBack(in:))
        case .goForward: window.map(platformOps.goForward(in:))
        case .openLocation: openLocation()
        }
    }

    /// The perform side of `WidgetCommand.openLocation` (#61): focuses the address bar with the
    /// whole address selected, reopening the widget first when there isn't one. The focus goes to
    /// the new window as soon as `openWidget()` has put it on screen — not after its startup page
    /// finishes loading, which would leave the user's first keystrokes going nowhere.
    private func openLocation() {
        if window == nil { openWidget() }
        guard let window else { return }
        platformOps.focusAddressBar(in: window)
    }

    /// Reloads the current page — the perform side of `WidgetCommand.reload` (#37's Display menu
    /// "重新载入页面", ⌘R). Also the settings panel's 刷新页面 button (#46), the one action that makes a
    /// script edit apply.
    public func reloadPage() {
        guard let window else { return }
        platformOps.reloadPage(in: window)
    }

    /// Stops the page's in-flight load — the perform side of `WidgetCommand.stop` (#60).
    private func stopLoading() {
        guard let window else { return }
        platformOps.stopLoading(in: window)
    }

    public func zoomIn() {
        applyZoomStep(Self.zoomStep)
    }

    public func zoomOut() {
        applyZoomStep(-Self.zoomStep)
    }

    /// Resets to 100% — #37's Display menu "实际大小" (⌘0).
    public func resetZoom() {
        guard let window else { return }
        currentZoom = 1.0
        platformOps.applyZoom(currentZoom, in: window)
    }

    /// Opens the settings panel — #37's Mochi menu "设置…" (⌘,), the same callback the toolbar's
    /// settings entry and the tray's 设置… item already share.
    public func openSettingsPanel() {
        openSettings()
    }

    /// Opens the standard About panel (#62) — the App menu's 关于 Mochi, and the one entry point
    /// the tray's 关于 Mochi is meant to reuse, so there is only ever one About. `openAbout`
    /// orders the panel front; activating afterwards (rather than before) makes the panel the key
    /// window when Mochi wasn't active — the tray case — instead of AppKit reaching for the
    /// widget, which in Ghost Mode must never become key (ADR-0012). The widget and its mode are
    /// left untouched either way. Activating an already-active app (the App menu case) is a no-op.
    public func openAboutPanel() {
        openAbout()
        platformOps.activateApp()
    }

    private func applyZoomStep(_ step: Double) {
        guard let window else { return }
        let clamped = min(max(currentZoom + step, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        currentZoom = clamped
        platformOps.applyZoom(currentZoom, in: window)
    }

    // MARK: 历史记录 (#102)

    /// The visit the page's title and icon belong to — the last one recorded (#114: they land on
    /// that visit alone), `nil` once the page has moved somewhere that isn't recorded.
    private var historyVisit: HistoryVisit.ID?
    /// `historyVisit`'s origin: an icon fetched for any other is not that visit's (#117).
    private var historyVisitOrigin: String?
    /// `historyVisit`'s address: the page reporting it again — a reload commits a new document at
    /// the same address — is the same visit, not a new one.
    private var historyVisitAddress: String?
    /// The last site icon the page got, and the origin it belongs to (#117) — what a visit
    /// within the same site (a `pushState` that loads nothing, so fetches no icon) is made under.
    private var historySiteIcon: (origin: String, png: Data)?

    /// Records the widget's main-page visits: `http`/`https` only, nothing while the Empty Page
    /// is up, Ghost Mode included (a video autoplaying the next one is still a visit). Popup
    /// Windows are never registered, so they never reach here.
    private func registerHistoryRecording(for window: WidgetWindowHandle, addressBarController: AddressBarController) {
        historyVisit = nil
        historyVisitOrigin = nil
        historyVisitAddress = nil
        historySiteIcon = nil
        platformOps.onMainFrameURLChanged(window) { [weak self, weak addressBarController] url in
            self?.recordHistoryVisit(to: url, isShowingEmptyPage: addressBarController?.isShowingEmptyPage ?? false)
        }
        platformOps.onSiteIconLoaded(window) { [weak self] pageURL, png in
            self?.updateHistorySiteIcon(png, for: pageURL)
        }
        addressBarController.onPageTitleChanged = { [weak self] title in
            self?.updateHistoryTitle(title)
        }
        // Leaving for the Empty Page ends the visit: coming back to the same address is a new one.
        addressBarController.onEmptyPageVisibilityChanged = { [weak self] isShowing in
            guard isShowing else { return }
            self?.historyVisit = nil
            self?.historyVisitOrigin = nil
            self?.historyVisitAddress = nil
        }
    }

    private func recordHistoryVisit(to url: URL, isShowingEmptyPage: Bool) {
        guard let historyStore, !isShowingEmptyPage, let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            historyVisit = nil
            historyVisitOrigin = nil
            historyVisitAddress = nil
            return
        }
        let address = HistoryStore.address(of: url)
        guard historyVisit == nil || address != historyVisitAddress else { return }
        let origin = Self.historyOrigin(of: url)
        // Only a move within the site the last visit was on — coming back from another site is a
        // change of site too, and waits for the icon its page loads.
        let staysOnSite = origin != nil && origin == historyVisitOrigin
        let icon = staysOnSite ? historySiteIcon.flatMap { $0.origin == origin ? $0.png : nil } : nil
        historyVisit = historyStore.recordVisit(to: url, favicon: icon)
        historyVisitOrigin = origin
        historyVisitAddress = address
    }

    /// #117: kept for the next visits within its site, and written to the current visit when it is
    /// that site's — never to a visit somewhere else.
    private func updateHistorySiteIcon(_ png: Data, for pageURL: URL) {
        guard let origin = Self.historyOrigin(of: pageURL) else { return }
        historySiteIcon = (origin, png)
        guard let historyVisit, historyVisitOrigin == origin else { return }
        historyStore?.updateFavicon(png, ofVisit: historyVisit)
    }

    /// The address bar's icon is per origin (`FaviconLoader`), case aside.
    private static func historyOrigin(of url: URL) -> String? {
        FaviconLoader.origin(of: url)?.lowercased()
    }

    private func updateHistoryTitle(_ title: String?) {
        guard let historyVisit, let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return }
        historyStore?.updateTitle(title, ofVisit: historyVisit)
    }

    /// The main menu's 历史记录 list, rebuilt from the store each time the menu opens — at the
    /// store's own "now", so the day boundaries are the ones the store groups by.
    public func historyMenu() -> HistoryMenu {
        guard let historyStore else { return HistoryMenu(today: [], earlierDays: []) }
        let now = historyStore.now()
        let earliest = HistoryMenu.earliestDay(now: now, calendar: historyStore.calendar)
        return HistoryMenu.build(visits: historyStore.visits(since: earliest), now: now, calendar: historyStore.calendar)
    }

    /// The PNG behind a 历史记录 menu item's `faviconID` (#117).
    public func historyFavicon(_ id: String) -> Data? {
        historyStore?.favicon(id)
    }

    /// Opens a page picked from history in the widget — reopening the widget first when it is
    /// closed. An explicit choice, so a Ghost Mode widget follows it *without* leaving Ghost Mode
    /// (`CONTEXT.md`): only the hotkey and the tray decide that, and `openWidget()` is not called
    /// on an existing widget for exactly that reason. Then the same path as typing the address —
    /// a reopened widget starts at the page rather than loading the startup content first.
    public func openFromHistory(_ url: URL) {
        guard window != nil else {
            openWidget(startingAt: url)
            persistURL(url)
            return
        }
        handleURLSubmitted(url)
    }

    /// #108: what the 历史记录 window (⌘Y) shows and does — the same store the menu is rebuilt
    /// from, so the menu follows whatever the window deletes, and the same `openFromHistory`.
    /// `nil` without a store. Its expired entries are judged by the retention configured at the
    /// moment it asks (#110).
    public func makeHistoryBrowser() -> HistoryBrowser? {
        guard let historyStore else { return nil }
        return HistoryBrowser(store: historyStore, retention: { [currentConfig] in currentConfig().historyRetention }) {
            [weak self] url in self?.openFromHistory(url)
        }
    }

    /// 移除历史记录项目 (#110) at launch; a settings edit and the 历史记录 window opening do the
    /// same through `SettingsController` and `HistoryBrowser`.
    private func removeExpiredHistory() {
        historyStore?.removeVisits(olderThan: currentConfig().historyRetention)
    }

    // MARK: 网页交互请求 (#66)

    /// Wires every page-initiated interaction request to its decision. Ghost Mode is read at
    /// request time — CONTEXT.md's "不打扰" rule: while in Ghost Mode nothing is shown, Ghost Mode
    /// is not left, and the request is settled at once so the page never hangs waiting. Follow-up
    /// request kinds (#67/#68/#69) register their own hook here, one line each.
    private func registerWebInteractionRequestHandlers(for window: WidgetWindowHandle) {
        platformOps.onJavaScriptDialogRequested(window) { [weak self] _ in
            (self?.isGhostModeActive ?? false) ? .settleWithoutUI : .presentSheet
        }
        platformOps.onFileUploadRequested(window) { [weak self] _ in
            (self?.isGhostModeActive ?? false) ? .cancel : .presentOpenPanel
        }
        // #68: setting and Ghost Mode are read now, at the moment of the download; the disk is
        // read off the main thread (#99), since the first touch of ~/Downloads waits on a prompt.
        platformOps.onDownloadRequested(window) { [weak self] request, completion in
            let config = self?.currentConfig()
            DownloadDestination.decide(
                suggestedFilename: request.suggestedFilename,
                location: config?.downloadLocation ?? .downloadsFolder,
                isGhostModeActive: self?.isGhostModeActive ?? false,
                fileSystem: self?.downloadFileSystem ?? .live,
                completion: completion)
        }
        // #105: how each download's write went, and the answer to 「无法存到下载文件夹」.
        platformOps.onDownloadEnded(window) { [weak self] outcome in
            self?.decideDownloadEnded(outcome) ?? .none
        }
        platformOps.onDownloadsFolderDeniedAnswered(window) { [weak self] answer in
            self?.followUpDownloadsFolderDenied(answer) ?? .none
        }

        // #69/#101 — settings, exceptions and the mode are read at request time; a fresh
        // controller per window, so a reopened widget has no 「仅这次允许」 left over.
        mediaCapturePermissions = MediaCapturePermissionController(
            platformOps: platformOps, window: window, currentConfig: currentConfig, persist: persist,
            isGhostModeActive: { [weak self] in self?.isGhostModeActive ?? false },
            now: { [weak self] in self?.currentDate() ?? Date() })

        platformOps.onNewWindowRequested(window) { [weak self] request in
            self?.decideNewWindow(request) ?? .cancel
        }
    }

    /// ADR-0017's routing (#67). A plain link click loads where it was clicked; a ⌘-click goes to
    /// the default browser; a script's `window.open` from the widget gets a Popup Window, and one
    /// from a Popup Window loads in place so popups never multiply.
    ///
    /// Ghost Mode opens nothing (CONTEXT.md): no Popup Window, no browser, and the click-through
    /// widget's page doesn't change underneath the user either. A Popup Window is an ordinary
    /// window Ghost Mode leaves alone — the user may be mid-login in it — so its own requests
    /// still load in place, which opens nothing new.
    private func decideNewWindow(_ request: NewWindowRequest) -> NewWindowDecision {
        if case .linkClick(commandPressed: true) = request.trigger {
            if !isGhostModeActive, let url = request.url {
                platformOps.openInDefaultBrowser(url)
            }
            return .cancel
        }
        switch request.opener {
        case .popupWindow:
            return .loadInOpener
        case .widget:
            if isGhostModeActive { return .cancel }
            if case .script = request.trigger { return .openPopupWindow }
            return .loadInOpener
        }
    }

    /// #68: the disk facts download destinations are decided against. Tests swap in a fake so
    /// nothing reads (let alone writes) the real ~/Downloads.
    public var downloadFileSystem: DownloadFileSystem = .live

    /// #101: stamps the 网页权限 exceptions remembered from Mochi's prompt. Tests swap in a fixed date.
    public var currentDate: () -> Date = { Date() }
    private var mediaCapturePermissions: MediaCapturePermissionController?

    /// #105 (ADR-0026): a write into the Downloads folder is the only reading of its permission
    /// there is. Refused → remembered, and offered another place — in Normal Mode only, Ghost Mode
    /// just remembers; succeeded → forgotten. A write anywhere else, or to a place picked in a Save
    /// panel, says nothing about it. Comparing paths reads no disk, so this is safe on the main
    /// thread (#99).
    private func decideDownloadEnded(_ outcome: DownloadOutcome) -> DownloadOutcomeDecision {
        let folder = outcome.destination.deletingLastPathComponent().standardizedFileURL.path
        guard !outcome.chosenInSavePanel, folder == downloadFileSystem.downloadsFolder.standardizedFileURL.path
        else { return .none }
        switch outcome.result {
        case .succeeded:
            platformOps.setSystemPermissionMarker(.downloadsFolderWriteDenied, false)
            return .none
        case .deniedPermission:
            platformOps.setSystemPermissionMarker(.downloadsFolderWriteDenied, true)
            return isGhostModeActive ? .none : .offerAnotherLocation
        case .failed:
            return .none
        }
    }

    /// #105: the answer to 「无法存到下载文件夹」, with Ghost Mode read again — nothing may show by
    /// then if the user has gone invisible in the meantime.
    private func followUpDownloadsFolderDenied(_ answer: DownloadsFolderDeniedAnswer) -> DownloadsFolderDeniedFollowUp {
        guard !isGhostModeActive else { return .none }
        switch answer {
        case .openSystemSettings:
            platformOps.openSystemSettings(for: .downloadsFolder)
            return .none
        case .saveElsewhere:
            return .saveElsewhereWithSavePanel
        case .cancel:
            return .none
        }
    }

    private var isGhostModeActive: Bool { ghostModeController?.mode == .ghost }

    private func handleNavigationFailed(_ message: String) {
        guard let window else { return }
        platformOps.showErrorPageContent(message: message, in: window)
    }

    /// Reads the enabled set and the custom script from the config on every navigation (#46) —
    /// which is exactly what "script edits apply on the next page load" means, with no
    /// notification needed. Already-executed JavaScript can't be undone, so this is as live as a
    /// script edit can honestly get; the settings panel's 刷新页面 button turns that next load
    /// into one click.
    private func injectConfiguredScripts() {
        guard let window else { return }
        let config = currentConfig()
        for script in BuiltInScripts.all where !config.disabledBuiltInScriptIDs.contains(script.id) {
            platformOps.injectScript(script.source, in: window)
        }
        if let customScript = config.customScript, !customScript.isEmpty {
            platformOps.injectScript(customScript, in: window)
        }
        if let customStylesheet = config.customStylesheet, !customStylesheet.isEmpty {
            platformOps.injectScript(CustomStylesheet.injectionSource(for: customStylesheet), in: window)
        }
    }

    /// Captures and persists the current window state. Called when the window closes,
    /// and again from app termination since quitting (e.g. Cmd+Q) does not always route
    /// through the window-close delegate callback. A no-op while the widget is closed — the
    /// geometry was already persisted on the way out.
    public func persistCurrentWindowState() {
        guard let window else { return }
        persistWindowState(platformOps.captureWindowState(of: window))
    }
}
