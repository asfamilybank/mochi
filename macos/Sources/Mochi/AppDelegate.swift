import AppKit
import MochiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var orchestrator: Orchestrator?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let platformOps = AppKitPlatformOps()
        let configURL = WidgetConfig.defaultConfigURL

        // A fresh install (no config file yet) is #16's expected "never configured/navigated
        // anywhere" state — falls back silently to a default, history-less config rather than
        // crashing the app on launch, and `Orchestrator` resolves that into the Empty Page rather
        // than a blank/broken window. A config file that *exists* but fails to load is a
        // different case (corruption, a bad hand-edit) — surfaced via an alert rather than
        // silently discarding the user's other settings (hotkey mappings, custom script, window
        // geometry) the same way a load failure would, and rather than the old
        // `fatalError` crashing the app outright.
        let initialConfig: WidgetConfig
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                initialConfig = try WidgetConfig.load(from: configURL)
            } catch {
                platformOps.presentAlert(
                    title: "配置文件读取失败",
                    message: "\(configURL.path) 无法解析，已使用默认设置启动：\(error)"
                )
                initialConfig = WidgetConfig()
            }
        } else {
            initialConfig = WidgetConfig()
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
