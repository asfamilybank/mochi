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
    /// Carbon's `cmdKey | optionKey`, shared by every default combo below. Hardcoded rather than
    /// importing Carbon here so this file stays platform-import-free like the rest of the pure
    /// MochiCore layer.
    private static let cmdOption: UInt32 = 0x0100 | 0x0800

    /// ⌥⌘G — the default Normal/Ghost Mode toggle (#8). `0x05` is `kVK_ANSI_G`.
    public static let toggleGhostMode = Hotkey(keyCode: 0x05, modifierFlags: cmdOption)

    /// ⌥⌘R — reloads the page (#12). `0x0F` is `kVK_ANSI_R`.
    public static let reloadPage = Hotkey(keyCode: 0x0F, modifierFlags: cmdOption)

    /// ⌥⌘= — zooms the page in (#12). `0x18` is `kVK_ANSI_Equal`.
    public static let zoomIn = Hotkey(keyCode: 0x18, modifierFlags: cmdOption)

    /// ⌥⌘- — zooms the page out (#12). `0x1B` is `kVK_ANSI_Minus`.
    public static let zoomOut = Hotkey(keyCode: 0x1B, modifierFlags: cmdOption)

    /// ⌥⌘H — the boss key (ADR-0012): hides/unhides the widget while Ghost Mode is active,
    /// leaving the page running. A silent no-op in Normal Mode, which is a plain macOS window
    /// (`⌘M` already minimizes it). Same combo as the old Normal-Mode-only 快速隐藏, with both
    /// its meaning and its scope swapped. `0x04` is `kVK_ANSI_H`.
    public static let hideWidget = Hotkey(keyCode: 0x04, modifierFlags: cmdOption)

    /// Every default combo, for callers (the settings panel's mapping editor, #14) that need to
    /// check a candidate trigger against Mochi's own reserved hotkeys *before* attempting to
    /// register it — `GlobalHotkeyRegistry`'s underlying `RegisterEventHotKey` does not fail on an
    /// in-process duplicate registration (it happily installs a second, independently-firing
    /// handler for the same combo instead — see `HotkeyForwarder`'s doc comment), so registration
    /// success/failure alone cannot be used to detect a collision with one of these.
    public static let all: [Hotkey] = [
        toggleGhostMode, reloadPage, zoomIn, zoomOut, hideWidget,
    ]
}
