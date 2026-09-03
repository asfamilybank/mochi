import AppKit
import MochiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?
    private var settingsWindowController: SettingsWindowController?

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
        // and vice versa. `SettingsController` (#13/#14/#15) is handed this same function, not a
        // copy of `currentConfig`, so a settings edit applies on top of it too.
        var currentConfig = initialConfig
        func persist(_ transform: (WidgetConfig) -> WidgetConfig) {
            currentConfig = transform(currentConfig)
            try? currentConfig.write(to: configURL)
        }

        let settingsController = SettingsController(
            platformOps: platformOps, currentConfig: { currentConfig }, persist: persist)
        let settingsViewModel = SettingsViewModel(controller: settingsController)
        let settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)
        self.settingsWindowController = settingsWindowController

        let orchestrator = Orchestrator(
            platformOps: platformOps,
            persistWindowState: { windowState in persist { $0.updatingWindowState(windowState) } },
            persistURL: { url in persist { $0.updatingURL(url) } },
            persistPinned: { isPinned in persist { $0.updatingPinned(isPinned) } },
            openSettings: { settingsWindowController.show() }
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
