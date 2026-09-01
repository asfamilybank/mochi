public final class Orchestrator {
    private let platformOps: PlatformOps
    private let persistWindowState: (WindowState) -> Void
    private var window: WidgetWindowHandle?

    public init(platformOps: PlatformOps, persistWindowState: @escaping (WindowState) -> Void = { _ in }) {
        self.platformOps = platformOps
        self.persistWindowState = persistWindowState
    }

    public func start(config: WidgetConfig) {
        let screens = platformOps.visibleScreens()
        let frame = WindowPlacement.resolve(persisted: config.windowState?.frame, visibleScreens: screens)
        let window = platformOps.createWidgetWindow(initialFrame: frame)
        self.window = window

        platformOps.loadURL(config.url, in: window)
        if let zoom = config.windowState?.zoom {
            platformOps.applyZoom(zoom, in: window)
        }
        platformOps.onWindowWillClose(window) { [weak self] in
            self?.persistCurrentWindowState()
        }
        platformOps.showWindow(window)
    }

    /// Captures and persists the current window state. Called when the window closes,
    /// and again from app termination since quitting (e.g. Cmd+Q) does not always route
    /// through the window-close delegate callback.
    public func persistCurrentWindowState() {
        guard let window else { return }
        persistWindowState(platformOps.captureWindowState(of: window))
    }
}
