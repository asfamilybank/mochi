public final class Orchestrator {
    private let platformOps: PlatformOps

    public init(platformOps: PlatformOps) {
        self.platformOps = platformOps
    }

    public func start(config: WidgetConfig) {
        let window = platformOps.createWidgetWindow()
        platformOps.loadURL(config.url, in: window)
        platformOps.showWindow(window)
    }
}
