import Combine
import Foundation
import MochiCore

/// Adapts `SettingsController` (MochiCore, framework-agnostic) to SwiftUI's `ObservableObject`
/// so `SettingsView` re-renders after every edit. Kept in the app target rather than MochiCore
/// since Combine/SwiftUI observation is a presentation concern, not something the testable
/// settings logic itself needs.
final class SettingsViewModel: ObservableObject {
    private let controller: SettingsController
    @Published private(set) var config: WidgetConfig

    init(controller: SettingsController) {
        self.controller = controller
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

    func updateCustomScript(_ script: String?) {
        controller.updateCustomScript(script)
        config = controller.config
    }

    func setBuiltInScript(_ id: String, enabled: Bool) {
        controller.setBuiltInScript(id, enabled: enabled)
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
