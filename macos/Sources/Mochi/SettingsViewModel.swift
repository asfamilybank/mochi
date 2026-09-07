import Combine
import Foundation
import MochiCore

/// Adapts `SettingsController` (MochiCore, framework-agnostic) to SwiftUI's `ObservableObject`
/// so `SettingsView` re-renders after every edit. Kept in the app target rather than MochiCore
/// since Combine/SwiftUI observation is a presentation concern, not something the testable
/// settings logic itself needs.
///
/// `config` is a *published mirror* re-read from the controller after each edit, not a second
/// source of truth: every mutation goes through the controller's persist path and this just
/// re-publishes what got persisted (#46's "no panel-local copy of the config" rule).
final class SettingsViewModel: ObservableObject {
    private let controller: SettingsController
    private let reloadPage: () -> Void
    @Published private(set) var config: WidgetConfig

    /// - Parameter reloadPage: the scripts tab's 刷新页面 button (#46) — the one click that makes a
    ///   script edit apply, since already-executed JavaScript can't be undone. Wired to
    ///   `Orchestrator.reloadPage`, the same operation the Display menu's ⌘R calls.
    init(controller: SettingsController, reloadPage: @escaping () -> Void) {
        self.controller = controller
        self.reloadPage = reloadPage
        self.config = controller.config
    }

    func updateStartupTarget(_ target: WidgetConfig.StartupTarget?) {
        controller.updateStartupTarget(target)
        config = controller.config
    }

    func updateGhostOpacity(_ opacity: Double) {
        controller.updateGhostOpacity(opacity)
        config = controller.config
    }

    func updateMouseAvoidanceEnabled(_ enabled: Bool) {
        controller.updateMouseAvoidanceEnabled(enabled)
        config = controller.config
    }

    func updateSnapEnabled(_ enabled: Bool) {
        controller.updateSnapEnabled(enabled)
        config = controller.config
    }

    func updateCustomScript(_ script: String?) {
        controller.updateCustomScript(script)
        config = controller.config
    }

    func setBuiltInScript(_ id: String, enabled: Bool) {
        controller.setBuiltInScript(id, enabled: enabled)
        config = controller.config
    }

    func reloadPageNow() {
        reloadPage()
    }

    @discardableResult
    func updateActionHotkey(_ action: HotkeyAction, to hotkey: Hotkey) -> Bool {
        let succeeded = controller.updateActionHotkey(action, to: hotkey)
        config = controller.config
        return succeeded
    }

    func resetActionHotkeysToDefaults() {
        controller.resetActionHotkeysToDefaults()
        config = controller.config
    }

    @discardableResult
    func addHotkeyMapping(trigger: Hotkey, pageKeystroke: Hotkey) -> Bool {
        let succeeded = controller.addHotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
        config = controller.config
        return succeeded
    }

    func removeHotkeyMapping(at index: Int) {
        controller.removeHotkeyMapping(at: index)
        config = controller.config
    }
}
