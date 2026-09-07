import AppKit
import MochiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var platformOps: AppKitPlatformOps?
    private var orchestrator: Orchestrator?
    private var settingsWindowController: SettingsWindowController?
    private var mainMenuBuilder: MainMenuBuilder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let platformOps = AppKitPlatformOps()
        self.platformOps = platformOps
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

        // Every reader and writer shares this one `currentConfig` (rather than each re-deriving
        // from `initialConfig`) so a URL persisted mid-session survives a later window-state
        // persist, and vice versa. `Orchestrator` and `SettingsController` are both handed the
        // same read closure and the same `persist` function, never a copy — the "read at the point
        // of use" discipline that makes every settings edit take effect without a restart (#46).
        var currentConfig = initialConfig
        func persist(_ transform: (WidgetConfig) -> WidgetConfig) {
            currentConfig = transform(currentConfig)
            try? currentConfig.write(to: configURL)
        }

        let orchestrator = Orchestrator(
            platformOps: platformOps,
            currentConfig: { currentConfig },
            persistWindowState: { windowState in persist { $0.updatingWindowState(windowState) } },
            persistURL: { url in persist { $0.updatingURL(url) } },
            openSettings: { [unowned self] in self.settingsWindowController?.show() }
        )
        self.orchestrator = orchestrator

        let settingsController = SettingsController(
            platformOps: platformOps, currentConfig: { currentConfig }, persist: persist,
            onGlobalHotkeyPressed: { orchestrator.handleGlobalHotkeyPressed($0) },
            configDidChange: { orchestrator.reapplyConfiguration() }
        )
        let settingsViewModel = SettingsViewModel(controller: settingsController, reloadPage: { orchestrator.reloadPage() })
        settingsWindowController = SettingsWindowController(viewModel: settingsViewModel)

        let mainMenuBuilder = MainMenuBuilder()
        self.mainMenuBuilder = mainMenuBuilder
        NSApp.mainMenu = mainMenuBuilder.build(orchestrator: orchestrator)

        orchestrator.start()
    }

    /// `false` since #42: closing the widget leaves Mochi running in the tray, exactly as the
    /// domain doc defines closing. `⌘Q` and the tray's 退出应用 are the only ways to terminate.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Dock-icon click while the widget is closed reopens it (#42), routed through `PlatformOps`
    /// so the core owns what "reopen" means. Returning `false` tells AppKit not to also apply its
    /// own default (un-minimizing whatever windows it can find) on top.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        platformOps?.handleApplicationReopen()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator?.persistCurrentWindowState()
    }
}
