import AppKit
import MochiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let platformOps = AppKitPlatformOps()
        let configURL = WidgetConfig.defaultConfigURL

        let config: WidgetConfig
        do {
            config = try WidgetConfig.load(from: configURL)
        } catch {
            fatalError("Failed to load widget config from \(configURL.path): \(error)")
        }

        let orchestrator = Orchestrator(platformOps: platformOps) { windowState in
            try? config.updatingWindowState(windowState).write(to: configURL)
        }
        self.orchestrator = orchestrator
        orchestrator.start(config: config)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator?.persistCurrentWindowState()
    }
}
