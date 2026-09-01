import AppKit
import MochiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let platformOps = AppKitPlatformOps()
        let orchestrator = Orchestrator(platformOps: platformOps)
        self.orchestrator = orchestrator

        do {
            let config = try WidgetConfig.load(from: WidgetConfig.defaultConfigURL)
            orchestrator.start(config: config)
        } catch {
            fatalError("Failed to load widget config from \(WidgetConfig.defaultConfigURL.path): \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
