import Foundation

public final class Orchestrator {
    /// The step `zoomIn`/`zoomOut` (#12) move by on each press, and the range they clamp to —
    /// matching a typical browser's zoom-shortcut feel rather than a jump straight to the extreme.
    private static let zoomStep = 0.1
    private static let zoomRange = 0.25...5.0

    private let platformOps: PlatformOps
    private let persistWindowState: (WindowState) -> Void
    private let persistURL: (URL) -> Void
    private let persistPinned: (Bool) -> Void
    private let openSettings: () -> Void
    private var window: WidgetWindowHandle?
    private var customScript: String?
    private var disabledBuiltInScriptIDs: Set<String> = []
    private var ghostModeController: GhostModeController?
    private var addressBarController: AddressBarController?
    private var hotkeyForwarder: HotkeyForwarder?
    private var currentZoom: Double = 1.0
    private var isPinned = false
    /// Independent of Ghost Mode's own hidden state — only ever toggled while in Normal Mode
    /// (see `handleQuickHideHotkey`), so it never fights ADR-0006's "only the Ghost Mode hotkey
    /// or the tray icon" rule for restoring visibility out of Ghost Mode.
    private var isQuickHidden = false

    public init(
        platformOps: PlatformOps,
        persistWindowState: @escaping (WindowState) -> Void = { _ in },
        persistURL: @escaping (URL) -> Void = { _ in },
        persistPinned: @escaping (Bool) -> Void = { _ in },
        openSettings: @escaping () -> Void = {}
    ) {
        self.platformOps = platformOps
        self.persistWindowState = persistWindowState
        self.persistURL = persistURL
        self.persistPinned = persistPinned
        self.openSettings = openSettings
    }

    public func start(config: WidgetConfig) {
        let screens = platformOps.visibleScreens()
        let frame = WindowPlacement.resolve(persisted: config.windowState?.frame, visibleScreens: screens)
        let window = platformOps.createWidgetWindow(initialFrame: frame)
        self.window = window
        self.customScript = config.customScript
        self.disabledBuiltInScriptIDs = config.disabledBuiltInScriptIDs
        self.currentZoom = config.windowState?.zoom ?? 1.0
        self.isPinned = config.isPinned

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
        platformOps.setPinned(config.isPinned, in: window)
        platformOps.setSnapThreshold(config.snapThreshold, in: window)
        platformOps.onWindowWillClose(window) { [weak self] in
            self?.persistCurrentWindowState()
        }
        platformOps.onURLSubmitted(window) { [weak self] url in
            self?.handleURLSubmitted(url)
        }
        platformOps.onPinnedChanged(window) { [weak self] pinned in
            self?.isPinned = pinned
            self?.persistPinned(pinned)
        }
        platformOps.onSettingsRequested(window) { [weak self] in
            self?.openSettings()
        }
        platformOps.onNavigationFinished(window) { [weak self] in
            self?.injectConfiguredScripts()
        }
        platformOps.showWindow(window)

        let ghostModeController = GhostModeController(platformOps: platformOps, window: window, ghostOpacity: config.ghostOpacity)
        self.ghostModeController = ghostModeController
        // Registered before `HotkeyForwarder` so its claimed combos can be passed down as
        // `reservedTriggers` — a user-configured mapping colliding with one of these must be
        // skipped, not registered a second time alongside it (see `HotkeyForwarder`'s doc comment).
        let reservedHotkeys = registerDefaultHotkeys(window: window, ghostModeController: ghostModeController)
        self.hotkeyForwarder = HotkeyForwarder(
            platformOps: platformOps, mappings: config.hotkeyMappings, reservedTriggers: reservedHotkeys,
            isGhostModeActive: { [weak ghostModeController] in ghostModeController?.mode == .ghost }
        )

        platformOps.createTrayIcon(items: [
            TrayMenuItem(title: "退出 Ghost Mode") { [weak self, weak ghostModeController] in
                ghostModeController?.exitGhostMode()
                self?.clearQuickHideIfNeeded()
            },
            TrayMenuItem(title: "切换 Ghost Mode") { [weak self, weak ghostModeController] in
                ghostModeController?.toggle()
                self?.clearQuickHideIfNeeded()
            },
            TrayMenuItem(title: "打开设置", action: openSettings),
            TrayMenuItem(title: "退出应用", action: platformOps.terminateApp),
        ])
    }

    /// Registers Ghost Mode's toggle hotkey and #12's utility hotkeys as a
    /// single batch, reusing `registerGlobalHotkey`'s existing conflict detection — failures are
    /// collected into one alert rather than one modal dialog per conflicting hotkey, since several
    /// could plausibly collide with other apps at once. Returns only the combos that actually
    /// registered successfully, for `HotkeyForwarder` to treat as reserved.
    @discardableResult
    private func registerDefaultHotkeys(window: WidgetWindowHandle, ghostModeController: GhostModeController) -> Set<Hotkey> {
        let registrations: [(name: String, hotkey: Hotkey, action: () -> Void)] = [
            ("切换 Ghost Mode", DefaultHotkeys.toggleGhostMode, { [weak self, weak ghostModeController] in
                ghostModeController?.toggle()
                self?.clearQuickHideIfNeeded()
            }),
            ("刷新页面", DefaultHotkeys.reloadPage, { [weak self] in self?.handleReloadHotkey() }),
            ("放大网页", DefaultHotkeys.zoomIn, { [weak self] in self?.handleZoomHotkey(step: Self.zoomStep) }),
            ("缩小网页", DefaultHotkeys.zoomOut, { [weak self] in self?.handleZoomHotkey(step: -Self.zoomStep) }),
            ("快速隐藏 Widget", DefaultHotkeys.quickHideWidget, { [weak self, weak ghostModeController] in
                self?.handleQuickHideHotkey(ghostModeController: ghostModeController)
            }),
            ("调整窗口尺寸", DefaultHotkeys.resizeWindow, { [weak self] in self?.handleResizeHotkey() }),
            ("切换置顶", DefaultHotkeys.togglePin, { [weak self] in self?.handleTogglePinHotkey() }),
        ]

        var failedNames: [String] = []
        var succeeded: Set<Hotkey> = []
        for (name, hotkey, action) in registrations {
            if platformOps.registerGlobalHotkey(hotkey, perform: action) {
                succeeded.insert(hotkey)
            } else {
                failedNames.append(name)
            }
        }
        if !failedNames.isEmpty {
            platformOps.presentAlert(
                title: "部分默认热键注册失败",
                message: "以下功能的默认热键已被其他应用占用，请检查冲突：\(failedNames.joined(separator: "、"))"
            )
        }
        return succeeded
    }

    private func handleURLSubmitted(_ url: URL) {
        guard let window else { return }
        platformOps.loadURL(url, in: window)
        addressBarController?.urlLoaded(url)
        persistURL(url)
    }

    private func handleReloadHotkey() {
        guard let window else { return }
        platformOps.reloadPage(in: window)
    }

    private func handleZoomHotkey(step: Double) {
        guard let window else { return }
        let clamped = min(max(currentZoom + step, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        currentZoom = clamped
        platformOps.applyZoom(currentZoom, in: window)
    }

    /// A no-op outside Normal Mode — Ghost Mode already owns the window's hidden state
    /// exclusively (ADR-0006), so this never introduces a second, independent way to change
    /// visibility while Ghost Mode is active.
    private func handleQuickHideHotkey(ghostModeController: GhostModeController?) {
        guard let window, ghostModeController?.mode == .normal else { return }
        isQuickHidden.toggle()
        platformOps.setWindowHidden(isQuickHidden, in: window)
    }

    /// Resets quick-hide's bookkeeping *and*, if it had actually hidden the window, restores
    /// visibility before Ghost Mode's own opacity/passthrough take over — called wherever Ghost
    /// Mode is entered or exited (hotkey and both tray items). Without the restore, a window
    /// quick-hidden in Normal Mode would stay invisible at the platform level even after entering
    /// Ghost Mode, which expects to start visible (only hiding once the mouse moves over it).
    private func clearQuickHideIfNeeded() {
        guard isQuickHidden, let window else { return }
        isQuickHidden = false
        platformOps.setWindowHidden(false, in: window)
    }

    private func handleResizeHotkey() {
        guard let window else { return }
        let currentFrame = platformOps.captureWindowState(of: window).frame
        let screens = platformOps.visibleScreens()
        // Clamp against whichever screen the window is actually on, not just the primary one —
        // otherwise resizing a window parked on a secondary display snaps it back onto the primary.
        let screen = screens.first(where: { $0.intersects(currentFrame.cgRect) }) ?? screens.first
            ?? CGRect(x: 0, y: 0, width: WindowPlacement.defaultWidth, height: WindowPlacement.defaultHeight)
        let nextFrame = WindowPlacement.togglingSize(current: currentFrame, in: screen)
        platformOps.setWindowFrame(nextFrame, in: window)
    }

    private func handleTogglePinHotkey() {
        guard let window else { return }
        isPinned.toggle()
        platformOps.setPinned(isPinned, in: window)
        persistPinned(isPinned)
    }

    private func injectConfiguredScripts() {
        guard let window else { return }
        for script in BuiltInScripts.all where !disabledBuiltInScriptIDs.contains(script.id) {
            platformOps.injectScript(script.source, in: window)
        }
        if let customScript, !customScript.isEmpty {
            platformOps.injectScript(customScript, in: window)
        }
    }

    /// Captures and persists the current window state. Called when the window closes,
    /// and again from app termination since quitting (e.g. Cmd+Q) does not always route
    /// through the window-close delegate callback.
    public func persistCurrentWindowState() {
        guard let window else { return }
        persistWindowState(platformOps.captureWindowState(of: window))
    }
}
