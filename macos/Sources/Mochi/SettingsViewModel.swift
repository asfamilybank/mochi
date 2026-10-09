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
    /// #70's 重新打开窗口 — `Orchestrator.reopenWidget`. Defaulted so other wiring stays untouched.
    var reopenWidget: () -> Void = {}
    @Published private(set) var config: WidgetConfig

    /// A row of the 热键 pane a refusal can be shown on (#86).
    enum HotkeyRowID: Hashable {
        case action(HotkeyAction)
        case videoControl(VideoControlAction)
        case newMapping
    }

    /// The last refused recording and the row it happened on (#86): that row shows the reason in
    /// red in place of its description, until the next recording starts or a few seconds pass.
    @Published private(set) var rowRejection: (row: HotkeyRowID, message: String)?
    private var rejectionExpiry: DispatchWorkItem?
    private static let rejectionDisplayDuration: TimeInterval = 4

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

    func updateSearchEngine(_ engine: SearchEngine) {
        controller.updateSearchEngine(engine)
        config = controller.config
    }

    func updateDownloadLocation(_ location: DownloadLocation) {
        controller.updateDownloadLocation(location)
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

    func updateCustomStylesheet(_ css: String?) {
        controller.updateCustomStylesheet(css)
        config = controller.config
    }

    func setBuiltInScript(_ id: String, enabled: Bool) {
        controller.setBuiltInScript(id, enabled: enabled)
        config = controller.config
    }

    // #70
    func updateAutoplayPolicy(_ policy: WidgetConfig.AutoplayPolicy) {
        controller.updateAutoplayPolicy(policy)
        config = controller.config
    }

    func updateMinimumFontSize(_ size: Int?) {
        controller.updateMinimumFontSize(size)
        config = controller.config
    }

    // #69
    func updateCameraPermission(_ permission: WidgetConfig.MediaCapturePermission) {
        controller.updateCameraPermission(permission)
        config = controller.config
    }

    func updateMicrophonePermission(_ permission: WidgetConfig.MediaCapturePermission) {
        controller.updateMicrophonePermission(permission)
        config = controller.config
    }

    // #67
    func updatePopupWindowPolicy(_ policy: WidgetConfig.PopupWindowPolicy) {
        controller.updatePopupWindowPolicy(policy)
        config = controller.config
    }

    func reopenWidgetNow() {
        reopenWidget()
    }

    // #72: 高级 pane
    func updateHTTPWarningEnabled(_ enabled: Bool) {
        controller.updateHTTPWarningEnabled(enabled)
        config = controller.config
    }

    func updateWebInspectorEnabled(_ enabled: Bool) {
        controller.updateWebInspectorEnabled(enabled)
        config = controller.config
    }

    func removeAllWebsiteData() {
        controller.removeAllWebsiteData()
    }

    func reloadPageNow() {
        reloadPage()
    }

    func updateActionHotkey(_ action: HotkeyAction, to hotkey: Hotkey?) {
        let rejection = controller.updateActionHotkey(action, to: hotkey)
        config = controller.config
        show(rejection, on: .action(action))
    }

    func rejectionMessage(for row: HotkeyRowID) -> String? {
        rowRejection?.row == row ? rowRejection?.message : nil
    }

    func clearRowRejection() {
        rejectionExpiry?.cancel()
        rejectionExpiry = nil
        rowRejection = nil
    }

    private func show(_ rejection: HotkeyRejection?, on row: HotkeyRowID) {
        clearRowRejection()
        guard let rejection else { return }
        rowRejection = (row, rejection.message)
        let expiry = DispatchWorkItem { [weak self] in self?.clearRowRejection() }
        rejectionExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.rejectionDisplayDuration, execute: expiry)
    }

    /// The panel's one 恢复默认 button covers both the action hotkeys and 视频控制 (#79). Video
    /// keys go first: one parked on an action's default would otherwise keep that action from
    /// being restored, though it is about to move off it itself.
    func resetHotkeysToDefaults() {
        controller.resetVideoControlToDefaults()
        controller.resetActionHotkeysToDefaults()
        config = controller.config
    }

    // MARK: 视频控制 (#79)

    /// Mirrors System Settings, which can change it behind Mochi's back — refreshed whenever the
    /// hotkeys pane appears and whenever the app comes back to the front.
    @Published private(set) var isAccessibilityTrusted = true

    func updateVideoControlTrigger(_ trigger: VideoControlTrigger?, for action: VideoControlAction) {
        let rejection = controller.updateVideoControlTrigger(trigger, for: action)
        config = controller.config
        show(rejection, on: .videoControl(action))
    }

    func updateVideoSeekStep(_ seconds: Int) {
        controller.updateVideoSeekStep(seconds)
        config = controller.config
    }

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = controller.isAccessibilityTrusted
    }

    func openAccessibilitySettings() {
        controller.openAccessibilitySettings()
    }

    /// `true` once the mapping is live; a refusal is shown on the add row instead.
    func addHotkeyMapping(trigger: Hotkey, pageKeystroke: Hotkey) -> Bool {
        let rejection = controller.addHotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
        config = controller.config
        show(rejection, on: .newMapping)
        return rejection == nil
    }

    func removeHotkeyMapping(at index: Int) {
        controller.removeHotkeyMapping(at: index)
        config = controller.config
    }
}
