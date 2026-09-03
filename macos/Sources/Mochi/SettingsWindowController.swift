import AppKit
import SwiftUI

/// Owns the settings panel's (#13) window — a single persistent instance reused across opens
/// (from either the toolbar's settings entry or the tray's "打开设置" item), rather than
/// recreated per-request, so its editing state (and the `SettingsViewModel` it observes) survives
/// being closed and reopened.
final class SettingsWindowController: NSWindowController {
    convenience init(viewModel: SettingsViewModel) {
        let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        self.init(window: window)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
