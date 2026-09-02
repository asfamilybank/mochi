import Foundation

/// A global hotkey, expressed as a platform virtual keycode + modifier-flag bitmask rather than
/// a semantic key name — deliberately thin, since registering it with the OS is `AppKitPlatformOps`'s
/// job (via Carbon's `RegisterEventHotKey`), not this pure layer's.
public struct Hotkey: Equatable {
    public var keyCode: UInt32
    public var modifierFlags: UInt32

    public init(keyCode: UInt32, modifierFlags: UInt32) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

public enum DefaultHotkeys {
    /// ⌥⌘G — the default Normal/Ghost Mode toggle (#8). `0x05` is `kVK_ANSI_G`; `0x0100 | 0x0800`
    /// is Carbon's `cmdKey | optionKey`. Hardcoded rather than importing Carbon here so this file
    /// stays platform-import-free like the rest of the pure MochiCore layer.
    public static let toggleGhostMode = Hotkey(keyCode: 0x05, modifierFlags: 0x0100 | 0x0800)
}
