import Foundation

/// One of the four modifier slots a recorder field always draws (#82), in the fixed order macOS
/// itself uses — so every row's combo lines up column for column, and an unbound field still
/// reads as a hotkey field, just an empty one.
public enum ModifierSlot: CaseIterable, Hashable, Sendable {
    case control, option, shift, command

    public var glyph: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    /// `Hotkey`'s Carbon bit for this modifier.
    var carbonFlag: UInt32 {
        switch self {
        case .control: 0x1000
        case .option: 0x0800
        case .shift: 0x0200
        case .command: 0x0100
        }
    }
}

/// What a recorder field draws (#82).
public enum RecorderFace: Equatable, Sendable {
    /// The four modifier slots, the `lit` ones in the accent color and the rest dim, then the key
    /// — `nil` when nothing is bound.
    case slots(lit: Set<ModifierSlot>, key: String?)
    /// A 视频控制 modifier tap: one cap naming its side ("右 ⌥"). It is pressed on its own, so
    /// lighting a slot would misread as "⌥ plus some key".
    case singleCap(String)
}

/// What a key pressed while a recorder is recording means (#82).
public enum RecorderKeyOutcome: Equatable, Sendable {
    /// Stop recording, keep what was bound.
    case cancel
    /// Unbind — the keyboard twin of the field's ⓧ.
    case clear
    case capture(Hotkey)
}

/// The rules every recorder in the settings panel shares — the action hotkeys', the mappings' and
/// 视频控制's — so the two recorder controls can't drift apart in how they look or what Esc does.
public enum HotkeyRecorderModel {
    private static let escapeKeyCode: UInt32 = 0x35
    private static let deleteKeyCodes: Set<UInt32> = [0x33, 0x75]  // ⌫, ⌦

    public static func face(of hotkey: Hotkey?) -> RecorderFace {
        guard let hotkey else { return .slots(lit: [], key: nil) }
        let lit = Set(ModifierSlot.allCases.filter { hotkey.modifierFlags & $0.carbonFlag != 0 })
        return .slots(lit: lit, key: HotkeyDisplay.keys(of: Hotkey(keyCode: hotkey.keyCode, modifierFlags: 0)).last)
    }

    public static func face(of trigger: VideoControlTrigger?) -> RecorderFace {
        switch trigger {
        case nil: face(of: nil as Hotkey?)
        case .modifierTap(let key)?: .singleCap(HotkeyDisplay.describe(.modifierTap(key)))
        case .keystroke(let hotkey)?: face(of: hotkey as Hotkey?)
        }
    }

    /// Only the bare Esc, ⌫ and ⌦ are taken over; with any modifier they are keys like any other.
    public static func outcome(ofKeyDown keyCode: UInt32, modifierFlags: UInt32) -> RecorderKeyOutcome {
        guard modifierFlags == 0 else { return .capture(Hotkey(keyCode: keyCode, modifierFlags: modifierFlags)) }
        if keyCode == escapeKeyCode { return .cancel }
        if deleteKeyCodes.contains(keyCode) { return .clear }
        return .capture(Hotkey(keyCode: keyCode, modifierFlags: 0))
    }
}
