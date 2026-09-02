import AppKit
import MochiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let platformOps = AppKitPlatformOps()
        let configURL = WidgetConfig.defaultConfigURL

        let initialConfig: WidgetConfig
        do {
            initialConfig = try WidgetConfig.load(from: configURL)
        } catch {
            fatalError("Failed to load widget config from \(configURL.path): \(error)")
        }

        // Both callbacks mutate the same `currentConfig` (rather than each re-deriving from
        // `initialConfig`) so a URL persisted mid-session survives a later window-state persist,
        // and vice versa.
        var currentConfig = initialConfig
        func persist(_ transform: (WidgetConfig) -> WidgetConfig) {
            currentConfig = transform(currentConfig)
            try? currentConfig.write(to: configURL)
        }

        let orchestrator = Orchestrator(
            platformOps: platformOps,
            persistWindowState: { windowState in persist { $0.updatingWindowState(windowState) } },
            persistURL: { url in persist { $0.updatingURL(url) } },
            persistPinned: { isPinned in persist { $0.updatingPinned(isPinned) } },
            // The settings panel itself is #13's scope, not yet built — this keeps the tray's
            // "打开设置" entry from being a silent no-op in the meantime.
            openSettings: {
                platformOps.presentAlert(
                    title: "设置面板尚未实现",
                    message: "设置面板正在开发中，敬请期待。"
                )
            }
        )
        self.orchestrator = orchestrator
        orchestrator.start(config: initialConfig)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator?.persistCurrentWindowState()
    }
}
