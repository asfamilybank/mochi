import Foundation

public final class Orchestrator {
    /// The step `zoomIn`/`zoomOut` (#37) move by on each call, and the range they clamp to —
    /// matching a typical browser's zoom-shortcut feel rather than a jump straight to the extreme.
    private static let zoomStep = 0.1
    private static let zoomRange = 0.25...5.0

    private let platformOps: PlatformOps
    private let currentConfig: () -> WidgetConfig
    private let persistWindowState: (WindowState) -> Void
    private let persistURL: (URL) -> Void
    private let openSettings: () -> Void
    private var window: WidgetWindowHandle?
    private var ghostModeController: GhostModeController?
    private var addressBarController: AddressBarController?
    private var hotkeyForwarder: HotkeyForwarder?
    private var currentZoom: Double = 1.0

    /// Whether a widget window currently exists (#42) — what the main menu's item validation
    /// asks to grey out 关闭窗口/刷新/缩放 while the widget is closed.
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
        openSettings: @escaping () -> Void = {}
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.persistWindowState = persistWindowState
        self.persistURL = persistURL
        self.openSettings = openSettings
    }

    /// Launch. Everything app-global — and therefore done exactly once, never again on a reopen
    /// (#42) — lives here: the tray icon (`NSStatusItem` is app-global; a second call would grow a
    /// second icon), the global hotkey registrations (Carbon hotkeys don't come and go with the
    /// widget window), and the Dock-reopen hook. The widget itself goes through `openWidget()`,
    /// the same operation a later reopen calls, so launch and reopen cannot drift apart.
    public func start() {
        hotkeyForwarder = HotkeyForwarder(
            platformOps: platformOps,
            isGhostModeActive: { [weak self] in self?.ghostModeController?.mode == .ghost }
        )
        registerGlobalHotkeys()
        platformOps.createTrayIcon(items: [
            // First, because while the widget is closed this is the one way back that's always on
            // screen (#42). Not greyed out when the widget is already open — the tray menu is built
            // once with no update hook, so both states get a sensible meaning instead.
            TrayMenuItem(title: "打开 Widget") { [weak self] in
                self?.openWidget()
            },
            TrayMenuItem(title: "退出 Ghost Mode") { [weak self] in
                self?.ghostModeController?.exitGhostMode()
            },
            TrayMenuItem(title: "切换 Ghost Mode") { [weak self] in
                self?.ghostModeController?.toggle()
            },
            TrayMenuItem(title: "打开设置", action: openSettings),
            TrayMenuItem(title: "退出应用", action: platformOps.terminateApp),
        ])
        platformOps.onReopenRequested { [weak self] in
            self?.openWidget()
        }
        openWidget()
    }

    /// Opens the widget window (#42) — at launch and again after a `⌘W`/red-button close. A
    /// reopen is defined as a fresh launch: startup content is re-resolved from the *current*
    /// config (so a fixed startup URL wins over whatever was being viewed at close), the page is
    /// loaded from scratch, and a brand-new `GhostModeController` means the widget is back in
    /// Normal Mode; only window geometry and zoom carry over, via the persisted `windowState`.
    ///
    /// Idempotent while a widget already exists: the tray's 打开 Widget entry then just brings it
    /// forward. If that widget is sitting in Ghost Mode this leaves Ghost Mode rather than fronting
    /// a click-through window — "bring it back so I can use it" is the only reading of the request
    /// that doesn't hand focus to a window ADR-0012 says may never be key.
    public func openWidget() {
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
        let window = platformOps.createWidgetWindow(initialFrame: frame)
        self.window = window
        self.currentZoom = config.windowState?.zoom ?? 1.0

        let addressBarController = AddressBarController(platformOps: platformOps, window: window)
        self.addressBarController = addressBarController

        switch StartupResolution.resolveStartupContent(for: config) {
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
        platformOps.onWindowWillClose(window) { [weak self] in
            self?.handleWindowWillClose()
        }
        platformOps.onURLSubmitted(window) { [weak self] url in
            self?.handleURLSubmitted(url)
        }
        platformOps.onSettingsRequested(window) { [weak self] in
            self?.openSettings()
        }
        platformOps.onNavigationFinished(window) { [weak self] in
            self?.injectConfiguredScripts()
        }
        platformOps.onNavigationFailed(window) { [weak self] message in
            self?.handleNavigationFailed(message)
        }
        platformOps.showWindow(window)

        let ghostModeController = GhostModeController(platformOps: platformOps, window: window, currentConfig: currentConfig)
        self.ghostModeController = ghostModeController
        // The toolbar button (#44) calls the exact same entry point as the hotkey and tray paths —
        // no shortcut path of its own — plus one thing only this path needs: giving up focus,
        // since a toolbar click is the one Ghost Mode entry route where Mochi is guaranteed to
        // already be active.
        platformOps.onGhostModeToggleRequested(window) { [weak self, weak ghostModeController] in
            ghostModeController?.toggle()
            self?.platformOps.deactivateApp()
        }
    }

    /// Really closes the widget (#42) — the File menu's 关闭窗口 (`⌘W`). Routes through the
    /// platform's close so the window's own will-close callback (`handleWindowWillClose`) does the
    /// teardown, exactly as it does for the red close button: one close path, one place that
    /// persists geometry first.
    public func closeWidget() {
        guard let window else { return }
        platformOps.closeWidgetWindow(window)
    }

    /// The single teardown point for both close entries. Persists geometry while the window still
    /// exists, then forgets every per-window object — from here on the two global hotkeys and the
    /// widget-bound menu items find no `ghostModeController`/`window` and silently do nothing, and
    /// the next `openWidget()` starts clean.
    private func handleWindowWillClose() {
        persistCurrentWindowState()
        window = nil
        ghostModeController = nil
        addressBarController = nil
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
        for action in HotkeyAction.allCases {
            let hotkey = config.hotkey(for: action)
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
        for mapping in config.hotkeyMappings {
            guard !registered.contains(mapping.trigger) else {
                mappingConflictCount += 1
                continue
            }
            if register(mapping.trigger) {
                registered.insert(mapping.trigger)
            } else {
                mappingConflictCount += 1
            }
        }
        if mappingConflictCount > 0 {
            platformOps.presentAlert(
                title: "热键映射注册失败",
                message: "\(mappingConflictCount) 条热键映射的触发热键已被其他应用或 Mochi 自身的热键占用，请检查冲突后调整映射。"
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
        if let mapping = config.hotkeyMappings.first(where: { $0.trigger == hotkey }) {
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
    /// pushed to the live window, and an opacity/avoidance edit made *while in Ghost Mode* has to
    /// be pushed down right now (see `GhostModeController.reapplyConfiguration`). Everything else
    /// in the config is read at its point of use and needs no call here. `SettingsController`
    /// invokes this after every persisted edit; a no-op while the widget is closed.
    public func reapplyConfiguration() {
        guard let window else { return }
        platformOps.setSnapEnabled(currentConfig().isSnapEnabled, in: window)
        ghostModeController?.reapplyConfiguration()
    }

    private func handleURLSubmitted(_ url: URL) {
        guard let window else { return }
        platformOps.loadURL(url, in: window)
        addressBarController?.urlLoaded(url)
        persistURL(url)
    }

    /// Reloads the current page — #37's Display menu "刷新" (⌘R), reachable through the responder
    /// chain since Mochi's main menu routes there rather than adding a `PlatformOps` method. Also
    /// the settings panel's 刷新页面 button (#46), the one action that makes a script edit apply.
    public func reloadPage() {
        guard let window else { return }
        platformOps.reloadPage(in: window)
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
    /// settings entry and the tray's "打开设置" item already share.
    public func openSettingsPanel() {
        openSettings()
    }

    private func applyZoomStep(_ step: Double) {
        guard let window else { return }
        let clamped = min(max(currentZoom + step, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        currentZoom = clamped
        platformOps.applyZoom(currentZoom, in: window)
    }

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
