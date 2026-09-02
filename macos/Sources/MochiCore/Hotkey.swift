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

    /// ⌥⌘T — Ghost Mode's secondary hotkey (#10) that temporarily summons the floating toolbar
    /// overlay without leaving Ghost Mode. `0x11` is `kVK_ANSI_T`.
    public static let summonToolbar = Hotkey(keyCode: 0x11, modifierFlags: cmdOption)

    /// ⌥⌘R — reloads the page (#12). `0x0F` is `kVK_ANSI_R`.
    public static let reloadPage = Hotkey(keyCode: 0x0F, modifierFlags: cmdOption)

    /// ⌥⌘= — zooms the page in (#12). `0x18` is `kVK_ANSI_Equal`.
    public static let zoomIn = Hotkey(keyCode: 0x18, modifierFlags: cmdOption)

    /// ⌥⌘- — zooms the page out (#12). `0x1B` is `kVK_ANSI_Minus`.
    public static let zoomOut = Hotkey(keyCode: 0x1B, modifierFlags: cmdOption)

    /// ⌥⌘H — quickly hides/unhides the widget window (#12), independent of Ghost Mode's own
    /// hide/show state machine (a no-op while Ghost Mode is active — see `Orchestrator` — so it
    /// never introduces a second, competing way to change visibility out from under ADR-0006's
    /// "only the Ghost Mode hotkey or the tray icon" rule). `0x04` is `kVK_ANSI_H`.
    public static let quickHideWidget = Hotkey(keyCode: 0x04, modifierFlags: cmdOption)

    /// ⌥⌘S — cycles the window between its default and compact preset sizes (#12), keeping the
    /// frame's origin fixed (see `WindowPlacement.togglingSize`). `0x01` is `kVK_ANSI_S`.
    public static let resizeWindow = Hotkey(keyCode: 0x01, modifierFlags: cmdOption)

    /// ⌥⌘P — toggles Pin (always-on-top), independent of Normal/Ghost Mode (#12).
    /// `0x23` is `kVK_ANSI_P`.
    public static let togglePin = Hotkey(keyCode: 0x23, modifierFlags: cmdOption)
}
