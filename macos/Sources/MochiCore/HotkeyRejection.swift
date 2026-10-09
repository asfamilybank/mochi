import Foundation

/// Why `SettingsController` refused a hotkey (#86) — named precisely enough that the settings
/// row it happened on can say what holds the combo, instead of one alert for every case.
public enum HotkeyRejection: Equatable, Sendable {
    case conflictsWithAction(HotkeyAction)
    case conflictsWithVideoControl(VideoControlAction)
    case conflictsWithMapping(HotkeyMapping)
    /// One of Mochi's own fixed menu shortcuts (`DefaultHotkeys.reservedLocalMenuShortcuts`).
    case reservedMenuShortcut
    /// The OS refused to register it: another app holds the combo.
    case heldByAnotherApp
    /// A combo with no ⌃/⌥/⌘ that still types a character (#89, ADR-0022) — see
    /// `Hotkey.keepsItsCharacter`.
    case missingModifier
    /// An ordinary key pressed while a tap is being recorded (#90).
    case needsModifierTap

    var isActionConflict: Bool {
        if case .conflictsWithAction = self { return true }
        return false
    }

    /// What the row shows in place of its description.
    public var message: String {
        switch self {
        case .conflictsWithAction(let action): "与「\(action.displayName)」冲突"
        case .conflictsWithVideoControl(let action): "与视频控制「\(action.displayName)」冲突"
        case .conflictsWithMapping(let mapping):
            "与映射「\(HotkeyDisplay.describe(mapping.trigger)) → \(HotkeyDisplay.describe(mapping.pageKeystroke))」冲突"
        case .reservedMenuShortcut: "这是 Mochi 菜单里的快捷键"
        case .heldByAnotherApp: "已被其他应用占用"
        case .missingModifier: "组合键至少要有 ⌃ ⌥ ⌘ 之一"
        case .needsModifierTap: "请轻按一颗修饰键"
        }
    }
}
