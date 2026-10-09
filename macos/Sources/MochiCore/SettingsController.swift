import Foundation

/// Drives every edit made in the settings panel (#13/#14/#15/#45/#46) — startup URL, Ghost Mode
/// opacity/Snap, the two action hotkeys, hotkey mapping CRUD, and custom/built-in script
/// management — exactly the way `Orchestrator` drives window/hotkey state: talking only to
/// `PlatformOps` plus an injected read/write pair, so it's exercisable against `FakePlatformOps`
/// without any AppKit/SwiftUI in the loop.
///
/// `currentConfig`/`persist` are a transform-based read-modify-write pair, not a cached copy of
/// the config handed in at init — mirroring `AppDelegate`'s own `persist(_:)` helper exactly, so a
/// settings edit is guaranteed to apply on top of whatever `Orchestrator` most recently persisted
/// (a window-state save, a URL navigation), never overwrite it with a stale snapshot taken
/// whenever the settings panel happened to open.
///
/// Every edit takes effect immediately (#45/#46): most settings are simply re-read by their
/// consumers at the point of use, so persisting *is* applying; the few that must be actively
/// pushed (Snap, an opacity edit made while in Ghost Mode) are covered by `configDidChange`, which
/// fires after every persisted edit and which the app wires to `Orchestrator.reapplyConfiguration`.
/// Hotkeys are the one kind of edit with an OS-level side effect, handled here directly as an
/// "unregister old → register new, roll back on failure" transaction before anything is persisted.
public final class SettingsController {
    private let platformOps: PlatformOps
    private let currentConfig: () -> WidgetConfig
    private let persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void
    private let onGlobalHotkeyPressed: (Hotkey) -> Void
    private let configDidChange: () -> Void

    public var config: WidgetConfig { currentConfig() }

    /// - Parameters:
    ///   - onGlobalHotkeyPressed: the handler every hotkey this controller registers dispatches
    ///     to — `Orchestrator.handleGlobalHotkeyPressed`, the same one launch-time registrations
    ///     use, so a combo bound here behaves identically to one bound at launch.
    ///   - configDidChange: a core-to-core notification (not a `PlatformOps` method) fired after
    ///     each persisted edit, for the settings that must be actively re-applied (#46).
    public init(
        platformOps: PlatformOps, currentConfig: @escaping () -> WidgetConfig,
        persist: @escaping (@escaping (WidgetConfig) -> WidgetConfig) -> Void,
        onGlobalHotkeyPressed: @escaping (Hotkey) -> Void = { _ in },
        configDidChange: @escaping () -> Void = {}
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.persist = persist
        self.onGlobalHotkeyPressed = onGlobalHotkeyPressed
        self.configDidChange = configDidChange
    }

    /// Every edit goes through here so `configDidChange` can never be forgotten for a new setting
    /// — hot-reload is the default, not something each setting opts into (#46).
    private func persistAndNotify(_ transform: @escaping (WidgetConfig) -> WidgetConfig) {
        persist(transform)
        configDidChange()
    }

    public func updateStartupTarget(_ target: WidgetConfig.StartupTarget?) {
        persistAndNotify { $0.updatingStartupTarget(target) }
    }

    public func updateGhostOpacity(_ opacity: Double) {
        persistAndNotify { $0.updatingGhostOpacity(opacity) }
    }

    public func updateSnapEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingSnapEnabled(enabled) }
    }

    /// #70 — applies on the next widget open (see `WidgetConfig.autoplayPolicy`).
    public func updateAutoplayPolicy(_ policy: WidgetConfig.AutoplayPolicy) {
        persistAndNotify { $0.updatingAutoplayPolicy(policy) }
    }

    /// #70 — `nil` removes the limit; pushed live through `configDidChange`.
    public func updateMinimumFontSize(_ size: Int?) {
        persistAndNotify { $0.updatingMinimumFontSize(size) }
    }

    /// #67 — pushed live through `configDidChange`.
    public func updatePopupWindowPolicy(_ policy: WidgetConfig.PopupWindowPolicy) {
        persistAndNotify { $0.updatingPopupWindowPolicy(policy) }
    }

    // #72: 高级 pane
    public func updateHTTPWarningEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingHTTPWarningEnabled(enabled) }
    }

    public func updateWebInspectorEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingWebInspectorEnabled(enabled) }
    }

    // #69: 网页内容 → 摄像头 / 麦克风 — read at each request, so persisting is applying.
    public func updateCameraPermission(_ permission: WidgetConfig.MediaCapturePermission) {
        persistAndNotify { $0.updatingCameraPermission(permission) }
    }

    public func updateMicrophonePermission(_ permission: WidgetConfig.MediaCapturePermission) {
        persistAndNotify { $0.updatingMicrophonePermission(permission) }
    }

    /// Not a config edit: nothing is persisted and `configDidChange` doesn't fire. The UI asks for
    /// confirmation before calling this.
    public func removeAllWebsiteData() {
        platformOps.removeAllWebsiteData()
    }

    public func updateSearchEngine(_ engine: SearchEngine) {
        persistAndNotify { $0.updatingSearchEngine(engine) }
    }

    /// #68 — read at each download, so persisting is applying.
    public func updateDownloadLocation(_ location: DownloadLocation) {
        persistAndNotify { $0.updatingDownloadLocation(location) }
    }

    public func updateCustomScript(_ script: String?) {
        persistAndNotify { $0.updatingCustomScript(script) }
    }

    public func updateCustomStylesheet(_ css: String?) {
        persistAndNotify { $0.updatingCustomStylesheet(css) }
    }

    public func setBuiltInScript(_ id: String, enabled: Bool) {
        persistAndNotify { config in
            var ids = config.disabledBuiltInScriptIDs
            if enabled { ids.remove(id) } else { ids.insert(id) }
            return config.updatingDisabledBuiltInScriptIDs(ids)
        }
    }

    // MARK: - #45: the two action hotkeys

    /// Rebinds `action` to `hotkey`, live, or clears it with `nil` (#85) — releasing the combo
    /// to other apps. Order matters: the old combo is released *before* the new one is claimed,
    /// since the new one might be the old one with a different action (a swap) — and if claiming
    /// fails (another app holds it), the old combo is re-registered and the config left
    /// untouched, so a failed attempt can never take away the hotkey the action had. A cleared
    /// action has nothing to release first, and nothing to fall back to: it stays cleared.
    ///
    /// Returns why it was refused (#86), or `nil` once the change is live.
    @discardableResult
    public func updateActionHotkey(_ action: HotkeyAction, to hotkey: Hotkey?) -> HotkeyRejection? {
        let current = currentConfig().hotkey(for: action)
        guard hotkey != current else { return nil }
        if let hotkey {
            if hotkey.keepsItsCharacter { return .missingModifier }
            if let conflict = inProcessConflict(with: hotkey, ignoringAction: action, ignoringMappingAt: nil) {
                return conflict
            }
            guard rebind(from: current, to: hotkey) else { return .heldByAnotherApp }
        } else if let current {
            platformOps.unregisterGlobalHotkey(current)
        }
        persistAndNotify { $0.updatingHotkeyOverride(action, to: hotkey) }
        return nil
    }

    /// Puts every overridden action back on its built-in combo, cleared ones included (#85) — the
    /// escape hatch for a user who bound both hotkeys to something odd and forgot what (#45). Each action is its own
    /// transaction with the same rollback rule as `updateActionHotkey`; one default being held —
    /// by another app, or in-process by a mapping or a video key — doesn't stop the other from
    /// being restored.
    public func resetActionHotkeysToDefaults() {
        var restored: [HotkeyAction] = []
        var failedNames: [String] = []
        for action in HotkeyAction.allCases {
            let current = currentConfig().hotkey(for: action)
            guard current != action.defaultHotkey else { continue }
            // Every action is on its way back to its own default and the defaults never collide,
            // so only something that isn't an action can be in the way.
            let conflict = inProcessConflict(with: action.defaultHotkey, ignoringAction: action, ignoringMappingAt: nil)
            if let conflict, !conflict.isActionConflict {
                failedNames.append(action.displayName)
            } else if rebind(from: current, to: action.defaultHotkey) {
                restored.append(action)
            } else {
                failedNames.append(action.displayName)
            }
        }
        if !restored.isEmpty {
            persistAndNotify { config in
                restored.reduce(config) { $0.updatingHotkeyOverride($1, to: $1.defaultHotkey) }
            }
        }
        if !failedNames.isEmpty {
            platformOps.presentAlert(
                title: "部分默认热键无法恢复",
                message: "以下功能的默认热键已被其他应用或 Mochi 的其他按键占用，已保留当前设置：\(failedNames.joined(separator: "、"))"
            )
        }
    }

    /// The unregister-then-register transaction shared by every live hotkey change, with the
    /// rollback that keeps "old released, new not claimed" from ever being an observable state.
    /// `old` is `nil` for a cleared action (#85): nothing to release, nothing to roll back to.
    private func rebind(from old: Hotkey?, to new: Hotkey) -> Bool {
        if let old { platformOps.unregisterGlobalHotkey(old) }
        if registerDispatching(new) { return true }
        if let old { platformOps.registerGlobalHotkey(old) { [onGlobalHotkeyPressed] in onGlobalHotkeyPressed(old) } }
        return false
    }

    private func registerDispatching(_ hotkey: Hotkey) -> Bool {
        platformOps.registerGlobalHotkey(hotkey) { [onGlobalHotkeyPressed] in onGlobalHotkeyPressed(hotkey) }
    }

    // MARK: - #14/#46: forwarding mappings

    /// Adds a new hotkey mapping (#14), live (#46). Conflict detection is two-tiered:
    ///
    /// 1. Combos already known in-process (the two action hotkeys at their *current* combos, the
    ///    fixed local menu shortcuts, or another entry already in the mapping table) are checked
    ///    directly against those — `GlobalHotkeyRegistry`'s underlying `RegisterEventHotKey` does
    ///    **not** fail on an in-process duplicate registration (it happily installs a second,
    ///    independently-firing handler for the same combo instead), so registration
    ///    success/failure alone cannot be trusted to catch these.
    /// 2. Anything left over is handed to `PlatformOps.registerGlobalHotkey` — reusing the same
    ///    OS-level check every other hotkey registration in the app already goes through — to
    ///    catch a combo another *application* holds. The registration this leaves behind is the
    ///    real one: it dispatches through `onGlobalHotkeyPressed`, which resolves the trigger to
    ///    its page keystroke against the config at press time, so the mapping forwards from the
    ///    moment it's persisted.
    ///
    /// Returns why it was refused (#86), or `nil` once the mapping is live.
    @discardableResult
    public func addHotkeyMapping(trigger: Hotkey, pageKeystroke: Hotkey) -> HotkeyRejection? {
        if trigger.keepsItsCharacter { return .missingModifier }
        if let conflict = inProcessConflict(with: trigger, ignoringAction: nil, ignoringMappingAt: nil) {
            return conflict
        }
        guard registerDispatching(trigger) else { return .heldByAnotherApp }
        persistAndNotify { $0.updatingHotkeyMappings($0.hotkeyMappings + [HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)]) }
        return nil
    }

    /// Re-runs the same two-tiered conflict check as `addHotkeyMapping` only when `trigger`
    /// actually changes, then swaps the OS registration as one unregister-old/register-new
    /// transaction with rollback (#46). Editing just the page-keystroke half never touches the OS
    /// hotkey table: the registered handler looks the page keystroke up at press time, so the
    /// persisted change is already live.
    ///
    /// Returns why it was refused (#86), or `nil` once the change is live — an index out of range
    /// is a no-op, not a refusal.
    @discardableResult
    public func updateHotkeyMapping(at index: Int, trigger: Hotkey, pageKeystroke: Hotkey) -> HotkeyRejection? {
        let mappings = currentConfig().hotkeyMappings
        guard mappings.indices.contains(index) else { return nil }
        let oldTrigger = mappings[index].trigger
        if trigger != oldTrigger {
            if trigger.keepsItsCharacter { return .missingModifier }
            if let conflict = inProcessConflict(with: trigger, ignoringAction: nil, ignoringMappingAt: index) {
                return conflict
            }
            guard rebind(from: oldTrigger, to: trigger) else { return .heldByAnotherApp }
        }
        persistAndNotify { config in
            var mappings = config.hotkeyMappings
            mappings[index] = HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
            return config.updatingHotkeyMappings(mappings)
        }
        return nil
    }

    /// Deleting a mapping hands its trigger back to the system immediately (#46) — the combo is
    /// genuinely released, not still intercepted until the next launch.
    public func removeHotkeyMapping(at index: Int) {
        let mappings = currentConfig().hotkeyMappings
        guard mappings.indices.contains(index) else { return }
        platformOps.unregisterGlobalHotkey(mappings[index].trigger)
        persistAndNotify { config in
            var mappings = config.hotkeyMappings
            guard mappings.indices.contains(index) else { return config }
            mappings.remove(at: index)
            return config.updatingHotkeyMappings(mappings)
        }
    }

    /// Whether `candidate` is already taken by something in this process, judged against the
    /// combos *actually in effect* — the action hotkeys at their current (possibly overridden)
    /// combos, not the built-in defaults (#45). Checking defaults would both miss a collision
    /// with a user's rebinding and wrongly refuse a combo that was a default but has since been
    /// released by being rebound.
    ///
    /// - Parameters:
    ///   - ignoringAction: the action being rebound, excluded so it can't collide with itself.
    ///   - ignoringMappingAt: the mapping index being edited, excluded for the same reason — `nil`
    ///     when adding a brand new mapping, where every existing entry counts.
    ///   - ignoringVideoAction: the 视频控制 action being rebound (#79), excluded the same way.
    ///
    /// Returns what already holds `candidate` (#86), or `nil` when nothing in-process does.
    private func inProcessConflict(
        with candidate: Hotkey, ignoringAction editedAction: HotkeyAction?, ignoringMappingAt editedIndex: Int?,
        ignoringVideoAction editedVideoAction: VideoControlAction? = nil
    ) -> HotkeyRejection? {
        let config = currentConfig()
        if let action = HotkeyAction.allCases.first(where: { $0 != editedAction && config.hotkey(for: $0) == candidate }) {
            return .conflictsWithAction(action)
        }
        if DefaultHotkeys.reservedLocalMenuShortcuts.contains(candidate) { return .reservedMenuShortcut }
        // A video key is never registered with the OS — it only listens — so an in-process check
        // is the only thing standing between it and a hotkey firing on the same press.
        if let action = VideoControlAction.allCases.first(where: {
            $0 != editedVideoAction && config.videoControlTrigger(for: $0) == .keystroke(candidate)
        }) {
            return .conflictsWithVideoControl(action)
        }
        let mapping = config.hotkeyMappings.enumerated().first { offset, mapping in
            offset != editedIndex && mapping.trigger == candidate
        }
        return mapping.map { .conflictsWithMapping($0.element) }
    }

    // MARK: - #79: 视频控制

    /// Binds a 视频控制 action to `trigger`, or clears it with `nil`. Nothing is registered with
    /// the OS — Video Control only listens (ADR-0020) — so the only conflicts are in-process: the
    /// action hotkeys, the local menu shortcuts, the mapping triggers, and the other video keys.
    /// Listening starts or stops through `configDidChange` when this binds the first key or
    /// clears the last.
    ///
    /// Returns why it was refused (#86), or `nil` once the change is live.
    @discardableResult
    public func updateTriggerKey(_ trigger: TriggerKey?, for action: VideoControlAction) -> HotkeyRejection? {
        let config = currentConfig()
        if let trigger, trigger != config.videoControlTrigger(for: action) {
            if let other = VideoControlAction.allCases.first(where: { $0 != action && config.videoControlTrigger(for: $0) == trigger }) {
                return .conflictsWithVideoControl(other)
            }
            if case .keystroke(let hotkey) = trigger, hotkey.keepsItsCharacter { return .missingModifier }
            if case .keystroke(let hotkey) = trigger,
               let conflict = inProcessConflict(with: hotkey, ignoringAction: nil, ignoringMappingAt: nil, ignoringVideoAction: action) {
                return conflict
            }
        }
        persistAndNotify { $0.updatingTriggerKey(trigger, for: action) }
        return nil
    }

    public func updateVideoSeekStep(_ seconds: Int) {
        persistAndNotify { $0.updatingVideoSeekStep(seconds) }
    }

    /// Every video key back on its default, and the jump length back to its default.
    public func resetVideoControlToDefaults() {
        persistAndNotify { config in
            VideoControlAction.allCases
                .reduce(config) { $0.updatingTriggerKey($1.defaultTrigger, for: $1) }
                .updatingVideoSeekStep(WidgetConfig.defaultVideoSeekStep)
        }
    }

    /// Read fresh each time — the user grants it in System Settings, outside Mochi.
    public var isAccessibilityTrusted: Bool { platformOps.isAccessibilityTrusted() }

    public func openAccessibilitySettings() {
        platformOps.openAccessibilitySettings()
    }
}
