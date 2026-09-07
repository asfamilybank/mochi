import Foundation

public final class Orchestrator {
    /// The step `zoomIn`/`zoomOut` (#37) move by on each call, and the range they clamp to —
    /// matching a typical browser's zoom-shortcut feel rather than a jump straight to the extreme.
    private static let zoomStep = 0.1
    private static let zoomRange = 0.25...5.0

    private let platformOps: PlatformOps
    private let persistWindowState: (WindowState) -> Void
    private let persistURL: (URL) -> Void
    private let openSettings: () -> Void
    private var window: WidgetWindowHandle?
    private var customScript: String?
    private var disabledBuiltInScriptIDs: Set<String> = []
    private var ghostModeController: GhostModeController?
    private var addressBarController: AddressBarController?
    private var hotkeyForwarder: HotkeyForwarder?
    private var currentZoom: Double = 1.0

    public init(
        platformOps: PlatformOps,
        persistWindowState: @escaping (WindowState) -> Void = { _ in },
        persistURL: @escaping (URL) -> Void = { _ in },
        openSettings: @escaping () -> Void = {}
    ) {
        self.platformOps = platformOps
        self.persistWindowState = persistWindowState
        self.persistURL = persistURL
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
            self?.persistCurrentWindowState()
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

        let ghostModeController = GhostModeController(
            platformOps: platformOps, window: window, ghostOpacity: config.ghostOpacity,
            isMouseAvoidanceEnabled: config.isMouseAvoidanceEnabled)
        self.ghostModeController = ghostModeController
        // The toolbar button (#44) calls the exact same entry point as the default hotkey and
        // tray icon below — no shortcut path of its own — plus one thing only this path needs:
        // giving up focus, since a toolbar click is the one Ghost Mode entry route where Mochi is
        // guaranteed to already be active.
        platformOps.onGhostModeToggleRequested(window) { [weak self, weak ghostModeController] in
            ghostModeController?.toggle()
            self?.platformOps.deactivateApp()
        }
        // Registered before `HotkeyForwarder` so its claimed combos can be passed down as
        // `reservedTriggers` — a user-configured mapping colliding with one of these must be
        // skipped, not registered a second time alongside it (see `HotkeyForwarder`'s doc comment).
        let reservedHotkeys = registerDefaultHotkeys(window: window, ghostModeController: ghostModeController)
        self.hotkeyForwarder = HotkeyForwarder(
            platformOps: platformOps, mappings: config.hotkeyMappings, reservedTriggers: reservedHotkeys,
            isGhostModeActive: { [weak ghostModeController] in ghostModeController?.mode == .ghost }
        )

        platformOps.createTrayIcon(items: [
            TrayMenuItem(title: "退出 Ghost Mode") { [weak ghostModeController] in
                ghostModeController?.exitGhostMode()
            },
            TrayMenuItem(title: "切换 Ghost Mode") { [weak ghostModeController] in
                ghostModeController?.toggle()
            },
            TrayMenuItem(title: "打开设置", action: openSettings),
            TrayMenuItem(title: "退出应用", action: platformOps.terminateApp),
        ])
    }

    /// Registers Ghost Mode's toggle hotkey and the boss key as a
    /// single batch, reusing `registerGlobalHotkey`'s existing conflict detection — failures are
    /// collected into one alert rather than one modal dialog per conflicting hotkey, since several
    /// could plausibly collide with other apps at once. Returns only the combos that actually
    /// registered successfully, for `HotkeyForwarder` to treat as reserved.
    ///
    /// Reload/zoom are *not* in this batch — #37 downgrades them from global hotkeys to local
    /// menu shortcuts (⌘R/⌘±/⌘0), reachable only while Mochi is the key window, which needs no
    /// Carbon registration at all.
    @discardableResult
    private func registerDefaultHotkeys(window: WidgetWindowHandle, ghostModeController: GhostModeController) -> Set<Hotkey> {
        let registrations: [(name: String, hotkey: Hotkey, action: () -> Void)] = [
            ("切换 Ghost Mode", DefaultHotkeys.toggleGhostMode, { [weak ghostModeController] in
                ghostModeController?.toggle()
            }),
            ("隐藏 Widget", DefaultHotkeys.hideWidget, { [weak ghostModeController] in
                ghostModeController?.toggleHidden()
            }),
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

    /// Reloads the current page — #37's Display menu "刷新" (⌘R), reachable through the responder
    /// chain since Mochi's main menu routes there rather than adding a `PlatformOps` method.
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
