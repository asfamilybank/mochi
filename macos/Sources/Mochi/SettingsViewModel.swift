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
/// re-publishes what got persisted (#46's "no panel-local copy of the config" rule). Writes made
/// outside the panel — the 询问框 remembering an exception (#109) — are re-read too, through
/// `SettingsController.onConfigPersisted`.
final class SettingsViewModel: ObservableObject {
    private let controller: SettingsController
    private let reloadPage: () -> Void
    /// #70's 重新打开窗口 — `Orchestrator.reopenWidget`. Defaulted so other wiring stays untouched.
    var reopenWidget: () -> Void = {}
    @Published private(set) var config: WidgetConfig {
        // Whether a 系统权限 prompt belongs on screen depends on the config too: unbinding every
        // key that needs input monitoring takes its prompt away (#111), and a 网页权限 or exception of
        // 拒绝 takes a page's (#104).
        didSet { refreshSystemPermissions() }
    }

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
        controller.onSystemPermissionsMayHaveChanged { [weak self] in self?.refreshSystemPermissions() }
        controller.onConfigPersisted { [weak self] in
            guard let self else { return }
            config = self.controller.config
        }
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

    // #109: 网站 → 摄像头 / 麦克风's exceptions table.
    func updatePagePermissionException(
        _ permission: PagePermission, host: String, setting: WidgetConfig.MediaCapturePermission
    ) {
        controller.updatePagePermissionException(permission, host: host, setting: setting)
        config = controller.config
    }

    func removePagePermissionExceptions(_ permission: PagePermission, hosts: Set<String>) {
        controller.removePagePermissionExceptions(permission, hosts: hosts)
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

    // MARK: 管理网站和数据… (#106)

    func fetchManagedWebsites(completion: @escaping ([ManagedWebsite]) -> Void) {
        controller.fetchManagedWebsites(completion: completion)
    }

    func removeWebsiteData(of websites: [ManagedWebsite], completion: @escaping () -> Void) {
        controller.removeWebsiteData(of: websites, completion: completion)
    }

    func removeDataOfAllWebsites(completion: @escaping () -> Void) {
        controller.removeDataOfAllWebsites(completion: completion)
    }

    func resetPagePermissions(of websites: [ManagedWebsite]) {
        controller.resetPagePermissions(of: websites)
        config = controller.config
    }

    // #107 — re-publishes the config, since clearing 网页权限例外 edits it.
    func clearBrowsingData(_ kinds: Set<BrowsingDataKind>, from range: BrowsingDataTimeRange) {
        controller.clearBrowsingData(kinds, from: range)
        config = controller.config
    }

    /// Whether 清除浏览数据… is showing over 隐私与安全性 — here rather than in the pane's own
    /// state so the 历史记录 menu's 清除浏览数据… can open the same sheet (#110).
    @Published var isClearingBrowsingData = false

    // #110
    func updateHistoryRetention(_ retention: HistoryRetention) {
        controller.updateHistoryRetention(retention)
        config = controller.config
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

    /// A key a recorder turned away while still recording (#90) — shown like a refusal.
    func showHint(_ rejection: HotkeyRejection, on row: HotkeyRowID) {
        show(rejection, on: row)
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

    func updateVideoControlTrigger(_ trigger: TriggerKey?, for action: VideoControlAction) {
        let rejection = controller.updateVideoControlTrigger(trigger, for: action)
        config = controller.config
        show(rejection, on: .videoControl(action))
    }

    func updateVideoSeekStep(_ seconds: Int) {
        controller.updateVideoSeekStep(seconds)
        config = controller.config
    }

    // MARK: 系统权限 (#98)

    /// Mirrors what the system reports, which System Settings can change behind Mochi's back —
    /// refreshed whenever a pane with a prompt appears and whenever a permission may have changed
    /// (`SettingsController.onSystemPermissionsMayHaveChanged`, wired up in `init`).
    @Published private(set) var systemPermissionPrompts: [SystemPermissionPrompt] = []

    func refreshSystemPermissions() {
        systemPermissionPrompts = controller.systemPermissionPrompts
    }

    func perform(_ prompt: SystemPermissionPrompt) {
        controller.perform(prompt)
    }

    /// 网站 → 摄像头 / 麦克风's prompt for `device`, if it has one (#104).
    func websitesPermissionPagePrompt(for device: SystemPermission) -> SystemPermissionPrompt? {
        systemPermissionPrompts.first { $0.placement == .websitesPermissionPage && $0.permission == device }
    }

    /// `true` once the mapping is live; a refusal is shown on the add row instead.
    func addHotkeyMapping(trigger: TriggerKey, pageKeystroke: Hotkey) -> Bool {
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
