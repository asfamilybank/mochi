import Foundation

/// A global hotkey, expressed as a platform virtual keycode + modifier-flag bitmask rather than
/// a semantic key name — deliberately thin, since registering it with the OS is `AppKitPlatformOps`'s
/// job (via Carbon's `RegisterEventHotKey`), not this pure layer's.
public struct Hotkey: Hashable {
    public var keyCode: UInt32
    public var modifierFlags: UInt32

    public init(keyCode: UInt32, modifierFlags: UInt32) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

public enum DefaultHotkeys {
    /// Carbon's `optionKey` alone, shared by both default action combos below. Hardcoded rather
    /// than importing Carbon here so this file stays platform-import-free like the rest of the
    /// pure MochiCore layer.
    ///
    /// Option-only rather than `⌥⌘` since #58: a Carbon hotkey is claimed system-wide for as long
    /// as Mochi runs, and `⌥⌘H` is every Mac app's 隐藏其他 — Mochi was stealing it from all of
    /// them. Accepted cost: while Mochi runs, ⌥G/⌥H no longer type `©`/`˙`, and terminals using
    /// Option-as-Meta lose `M-g`/`M-h`. Users who rebound either action keep their combo — the
    /// config stores only overrides.
    private static let option: UInt32 = 0x0800

    /// ⌥G — the default Normal/Ghost Mode toggle (#8, ⌥⌘G before #58). `0x05` is `kVK_ANSI_G`.
    public static let toggleGhostMode = Hotkey(keyCode: 0x05, modifierFlags: option)

    /// ⌥H — the boss key (ADR-0012, ⌥⌘H before #58): hides/unhides the widget while Ghost Mode
    /// is active, leaving the page running. A silent no-op in Normal Mode, which is a plain macOS
    /// window (`⌘M` already minimizes it). `0x04` is `kVK_ANSI_H`.
    public static let hideWidget = Hotkey(keyCode: 0x04, modifierFlags: option)

    /// Plain `⌘`, no `⌥` — shared by every fixed local menu shortcut below.
    private static let cmd: UInt32 = 0x0100

    /// ⌘, — the main menu's 设置…, a fixed local shortcut rather than a global hotkey (see
    /// `reservedLocalMenuShortcuts`). Named on its own because the Empty Page lists it.
    /// `0x2B` is `kVK_ANSI_Comma`.
    public static let openSettings = Hotkey(keyCode: 0x2B, modifierFlags: cmd)

    /// The fixed local menu shortcuts #37 built into `MainMenuBuilder` (⌘R/⌘+/⌘-/⌘0/⌘,) — never
    /// routed through `GlobalHotkeyRegistry` at all (a local `NSMenuItem` key equivalent only
    /// dispatches through the responder chain while Mochi is the key window), but still listed
    /// here so a user-configured hotkey-forwarding mapping (#14) can't silently claim the same
    /// combo: Carbon's `RegisterEventHotKey` has no visibility into AppKit's local key-equivalent
    /// dispatch, so without this a mapping's trigger and one of these shortcuts would both fire
    /// on a single keypress whenever Mochi has focus (code review finding, #36/#37/#38/#44
    /// review).
    public static let reservedLocalMenuShortcuts: [Hotkey] = [
        Hotkey(keyCode: 0x0F, modifierFlags: cmd),  // ⌘R 刷新, kVK_ANSI_R
        Hotkey(keyCode: 0x18, modifierFlags: cmd),  // ⌘+ 放大, kVK_ANSI_Equal
        Hotkey(keyCode: 0x1B, modifierFlags: cmd),  // ⌘- 缩小, kVK_ANSI_Minus
        Hotkey(keyCode: 0x1D, modifierFlags: cmd),  // ⌘0 实际大小, kVK_ANSI_0
        openSettings,                               // ⌘, 设置…
        Hotkey(keyCode: 0x21, modifierFlags: cmd),  // ⌘[ 返回 (#59), kVK_ANSI_LeftBracket
        Hotkey(keyCode: 0x1E, modifierFlags: cmd),  // ⌘] 前进 (#59), kVK_ANSI_RightBracket
        Hotkey(keyCode: 0x25, modifierFlags: cmd),  // ⌘L 打开位置…, kVK_ANSI_L
    ]
}

/// The two actions Mochi binds a *global* (Carbon-registered) hotkey to — and, since #45, the only
/// two: reload/zoom/settings are fixed local menu shortcuts (#37) and deliberately not
/// customizable, matching Chrome.
///
/// Each case's `rawValue` is the stable string identifier the config file stores an override
/// under (`[hotkeys]` table) — an explicit constant per case, never the case's declaration order
/// or an integer index, so reordering or adding cases can't silently rebind a user's saved combo.
public enum HotkeyAction: String, CaseIterable, Hashable {
    case toggleGhostMode = "toggle_ghost_mode"
    case hideWidget = "hide_widget"

    /// The built-in combo that applies when the user hasn't overridden this action
    /// (`WidgetConfig.hotkey(for:)`).
    public var defaultHotkey: Hotkey {
        switch self {
        case .toggleGhostMode: DefaultHotkeys.toggleGhostMode
        case .hideWidget: DefaultHotkeys.hideWidget
        }
    }

    public var displayName: String {
        switch self {
        case .toggleGhostMode: "切换幽灵模式"
        case .hideWidget: "隐藏窗口"
        }
    }
}
