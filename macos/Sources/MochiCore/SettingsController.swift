import Foundation

/// Drives every edit made in the settings panel (#13/#14/#15/#45/#46) — startup URL, Ghost Mode
/// opacity/avoidance/Snap, the two action hotkeys, hotkey mapping CRUD, and custom/built-in script
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

    public func updateMouseAvoidanceEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingMouseAvoidanceEnabled(enabled) }
    }

    public func updateSnapEnabled(_ enabled: Bool) {
        persistAndNotify { $0.updatingSnapEnabled(enabled) }
    }

    public func updateCustomScript(_ script: String?) {
        persistAndNotify { $0.updatingCustomScript(script) }
    }

    public func setBuiltInScript(_ id: String, enabled: Bool) {
        persistAndNotify { config in
            var ids = config.disabledBuiltInScriptIDs
            if enabled { ids.remove(id) } else { ids.insert(id) }
            return config.updatingDisabledBuiltInScriptIDs(ids)
        }
    }

    // MARK: - #45: the two action hotkeys

    /// Rebinds `action` to `hotkey`, live. Order matters: the old combo is released *before* the
    /// new one is claimed, since the new one might be the old one with a different action (a swap)
    /// — and if claiming fails (another app holds it), the old combo is re-registered and the
    /// config left untouched, so a failed attempt can never leave the action with no hotkey at all.
    @discardableResult
    public func updateActionHotkey(_ action: HotkeyAction, to hotkey: Hotkey) -> Bool {
        let current = currentConfig().hotkey(for: action)
        guard hotkey != current else { return true }
        guard !isReservedInProcess(hotkey, ignoringAction: action, ignoringMappingAt: nil) else {
            presentConflictAlert()
            return false
        }
        guard rebind(from: current, to: hotkey) else {
            presentConflictAlert()
            return false
        }
        persistAndNotify { $0.updatingHotkeyOverride(action, to: hotkey) }
        return true
    }

    /// Puts every overridden action back on its built-in combo — the escape hatch for a user who
    /// bound both hotkeys to something odd and forgot what (#45). Each action is its own
    /// transaction with the same rollback rule as `updateActionHotkey`; one default being held by
    /// another app doesn't stop the other from being restored.
    public func resetActionHotkeysToDefaults() {
        var restored: [HotkeyAction] = []
        var failedNames: [String] = []
        for action in HotkeyAction.allCases {
            let current = currentConfig().hotkey(for: action)
            guard current != action.defaultHotkey else { continue }
            if rebind(from: current, to: action.defaultHotkey) {
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
                message: "以下功能的默认热键已被其他应用占用，已保留当前设置：\(failedNames.joined(separator: "、"))"
            )
        }
    }

    /// The unregister-then-register transaction shared by every live hotkey change, with the
    /// rollback that keeps "old released, new not claimed" from ever being an observable state.
    private func rebind(from old: Hotkey, to new: Hotkey) -> Bool {
        platformOps.unregisterGlobalHotkey(old)
        if registerDispatching(new) { return true }
        platformOps.registerGlobalHotkey(old) { [onGlobalHotkeyPressed] in onGlobalHotkeyPressed(old) }
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
    @discardableResult
    public func addHotkeyMapping(trigger: Hotkey, pageKeystroke: Hotkey) -> Bool {
        guard !isReservedInProcess(trigger, ignoringAction: nil, ignoringMappingAt: nil) else {
            presentConflictAlert()
            return false
        }
        guard registerDispatching(trigger) else {
            presentConflictAlert()
            return false
        }
        persistAndNotify { $0.updatingHotkeyMappings($0.hotkeyMappings + [HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)]) }
        return true
    }

    /// Re-runs the same two-tiered conflict check as `addHotkeyMapping` only when `trigger`
    /// actually changes, then swaps the OS registration as one unregister-old/register-new
    /// transaction with rollback (#46). Editing just the page-keystroke half never touches the OS
    /// hotkey table: the registered handler looks the page keystroke up at press time, so the
    /// persisted change is already live.
    @discardableResult
    public func updateHotkeyMapping(at index: Int, trigger: Hotkey, pageKeystroke: Hotkey) -> Bool {
        let mappings = currentConfig().hotkeyMappings
        guard mappings.indices.contains(index) else { return false }
        let oldTrigger = mappings[index].trigger
        if trigger != oldTrigger {
            guard !isReservedInProcess(trigger, ignoringAction: nil, ignoringMappingAt: index) else {
                presentConflictAlert()
                return false
            }
            guard rebind(from: oldTrigger, to: trigger) else {
                presentConflictAlert()
                return false
            }
        }
        persistAndNotify { config in
            var mappings = config.hotkeyMappings
            mappings[index] = HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
            return config.updatingHotkeyMappings(mappings)
        }
        return true
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
    private func isReservedInProcess(_ candidate: Hotkey, ignoringAction editedAction: HotkeyAction?, ignoringMappingAt editedIndex: Int?) -> Bool {
        let config = currentConfig()
        if HotkeyAction.allCases.contains(where: { $0 != editedAction && config.hotkey(for: $0) == candidate }) { return true }
        if DefaultHotkeys.reservedLocalMenuShortcuts.contains(candidate) { return true }
        return config.hotkeyMappings.enumerated().contains { offset, mapping in
            offset != editedIndex && mapping.trigger == candidate
        }
    }

    private func presentConflictAlert() {
        platformOps.presentAlert(
            title: "热键已被占用",
            message: "该热键已经在使用中（可能是另一个映射、Mochi 的另一个功能热键，或另一个应用），请选择其他组合。"
        )
    }
}
