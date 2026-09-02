import Foundation

public final class Orchestrator {
    private let platformOps: PlatformOps
    private let persistWindowState: (WindowState) -> Void
    private let persistURL: (URL) -> Void
    private let persistPinned: (Bool) -> Void
    private let openSettings: () -> Void
    private var window: WidgetWindowHandle?
    private var customScript: String?
    private var ghostModeController: GhostModeController?

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

        platformOps.loadURL(config.url, in: window)
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
            self?.persistPinned(pinned)
        }
        platformOps.onNavigationFinished(window) { [weak self] in
            self?.injectConfiguredScripts()
        }
        platformOps.showWindow(window)

        let ghostModeController = GhostModeController(platformOps: platformOps, window: window, ghostOpacity: config.ghostOpacity)
        self.ghostModeController = ghostModeController
        let registered = platformOps.registerGlobalHotkey(DefaultHotkeys.toggleGhostMode) { [weak ghostModeController] in
            ghostModeController?.toggle()
        }
        if !registered {
            platformOps.presentAlert(
                title: "热键注册失败",
                message: "默认的 Ghost Mode 切换热键已被其他应用占用，请检查快捷键冲突后重启 Mochi。"
            )
        }

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

    private func handleURLSubmitted(_ url: URL) {
        guard let window else { return }
        platformOps.loadURL(url, in: window)
        persistURL(url)
    }

    private func injectConfiguredScripts() {
        guard let window else { return }
        for script in BuiltInScripts.all {
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
