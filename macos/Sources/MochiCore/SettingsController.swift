import Foundation

/// Drives every edit made in the settings panel (#13/#14/#15) — startup URL / Ghost Mode opacity,
/// hotkey mapping CRUD, and custom/built-in script management — exactly the way `Orchestrator`
/// drives window/hotkey state: talking only to `PlatformOps` plus an injected read/write pair, so
/// it's exercisable against `FakePlatformOps` without any AppKit/SwiftUI in the loop.
///
/// `currentConfig`/`persist` are a transform-based read-modify-write pair, not a cached copy of
/// the config handed in at init — mirroring `AppDelegate`'s own `persist(_:)` helper exactly, so a
/// settings edit is guaranteed to apply on top of whatever `Orchestrator` most recently persisted
/// (a window-state save, a URL navigation, a Pin toggle), never overwrite it with a stale
/// snapshot taken whenever the settings panel happened to open.
public final class SettingsController {
    private let platformOps: PlatformOps
    private let currentConfig: () -> WidgetConfig
    private let persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void

    public var config: WidgetConfig { currentConfig() }

    public init(
        platformOps: PlatformOps, currentConfig: @escaping () -> WidgetConfig,
        persist: @escaping (@escaping (WidgetConfig) -> WidgetConfig) -> Void
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.persist = persist
    }

    public func updateStartupTarget(_ target: WidgetConfig.StartupTarget?) {
        persist { $0.updatingStartupTarget(target) }
    }

    public func updateGhostOpacity(_ opacity: Double) {
        persist { $0.updatingGhostOpacity(opacity) }
    }

    public func updateCustomScript(_ script: String?) {
        persist { $0.updatingCustomScript(script) }
    }

    public func setBuiltInScript(_ id: String, enabled: Bool) {
        persist { config in
            var ids = config.disabledBuiltInScriptIDs
            if enabled { ids.remove(id) } else { ids.insert(id) }
            return config.updatingDisabledBuiltInScriptIDs(ids)
        }
    }

    /// Adds a new hotkey mapping (#14). Conflict detection is two-tiered:
    ///
    /// 1. Combos already known in-process (Mochi's own default hotkeys, or another entry already
    ///    in the mapping table) are checked directly against those lists — `GlobalHotkeyRegistry`'s
    ///    underlying `RegisterEventHotKey` does **not** fail on an in-process duplicate
    ///    registration (it happily installs a second, independently-firing handler for the same
    ///    combo instead, per `HotkeyForwarder`'s doc comment), so registration success/failure
    ///    alone cannot be trusted to catch these.
    /// 2. Anything left over is handed to `PlatformOps.registerGlobalHotkey` — reusing the same
    ///    OS-level check every other hotkey registration in the app already goes through — to
    ///    catch a combo another *application* holds. The registration this leaves behind is a
    ///    harmless no-op handler, superseded the next time the app launches and `HotkeyForwarder`
    ///    is rebuilt from the persisted mappings.
    @discardableResult
    public func addHotkeyMapping(trigger: Hotkey, pageKeystroke: Hotkey) -> Bool {
        guard !isReservedInProcess(trigger, ignoringMappingAt: nil) else {
            presentConflictAlert()
            return false
        }
        guard platformOps.registerGlobalHotkey(trigger, perform: {}) else {
            presentConflictAlert()
            return false
        }
        persist { $0.updatingHotkeyMappings($0.hotkeyMappings + [HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)]) }
        return true
    }

    /// Re-runs the same two-tiered conflict check as `addHotkeyMapping` only when `trigger`
    /// actually changes — editing just the page-keystroke half of a mapping never touches the OS
    /// hotkey table, so there is nothing to re-validate.
    @discardableResult
    public func updateHotkeyMapping(at index: Int, trigger: Hotkey, pageKeystroke: Hotkey) -> Bool {
        let mappings = currentConfig().hotkeyMappings
        guard mappings.indices.contains(index) else { return false }
        if trigger != mappings[index].trigger {
            guard !isReservedInProcess(trigger, ignoringMappingAt: index) else {
                presentConflictAlert()
                return false
            }
            guard platformOps.registerGlobalHotkey(trigger, perform: {}) else {
                presentConflictAlert()
                return false
            }
        }
        persist { config in
            var mappings = config.hotkeyMappings
            mappings[index] = HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
            return config.updatingHotkeyMappings(mappings)
        }
        return true
    }

    /// - Parameter ignoringMappingAt: the index being edited, excluded from the self-collision
    ///   check — `nil` when adding a brand new mapping, where every existing entry counts.
    private func isReservedInProcess(_ trigger: Hotkey, ignoringMappingAt editedIndex: Int?) -> Bool {
        if DefaultHotkeys.all.contains(trigger) { return true }
        return currentConfig().hotkeyMappings.enumerated().contains { offset, mapping in
            offset != editedIndex && mapping.trigger == trigger
        }
    }

    public func removeHotkeyMapping(at index: Int) {
        persist { config in
            guard config.hotkeyMappings.indices.contains(index) else { return config }
            var mappings = config.hotkeyMappings
            mappings.remove(at: index)
            return config.updatingHotkeyMappings(mappings)
        }
    }

    private func presentConflictAlert() {
        platformOps.presentAlert(
            title: "热键已被占用",
            message: "该触发热键已经在使用中（可能是另一个映射、Mochi 的默认热键，或另一个应用），请选择其他组合。"
        )
    }
}
