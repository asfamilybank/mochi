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

/// What a recorder is recording (#90): a trigger key of a given kind, or the page key a mapping
/// sends — which, being a keystroke to send rather than one to listen for, may be anything.
public enum RecorderTarget: Equatable, Sendable {
    case trigger(TriggerKind)
    case pageKeystroke
}

/// What a key pressed while a recorder is recording means (#82).
public enum RecorderKeyOutcome: Equatable, Sendable {
    /// Stop recording, keep what was bound.
    case cancel
    /// Unbind — the keyboard twin of the field's ⓧ.
    case clear
    case capture(Hotkey)
    /// A modifier pressed on its own, once or twice.
    case captureTap(ModifierTapEvent)
    /// Keep recording and say on the row why that key wasn't taken (#90).
    case hint(HotkeyRejection)
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
        case .modifierDoubleTap(let key)?: .singleCap(HotkeyDisplay.describe(.modifierDoubleTap(key)))
        case .keystroke(let hotkey)?: face(of: hotkey as Hotkey?)
        }
    }

    /// Only the bare Esc, ⌫ and ⌦ are taken over; with any modifier they are keys like any other.
    /// Past those, a key records only if it fits `target`: a combo that keeps its character
    /// (#89), or any key at all while a tap is wanted, is turned away with a hint instead.
    public static func outcome(ofKeyDown keyCode: UInt32, modifierFlags: UInt32, recording target: RecorderTarget) -> RecorderKeyOutcome {
        if modifierFlags == 0 {
            if keyCode == escapeKeyCode { return .cancel }
            if deleteKeyCodes.contains(keyCode) { return .clear }
        }
        let hotkey = Hotkey(keyCode: keyCode, modifierFlags: modifierFlags)
        switch target {
        case .pageKeystroke: return .capture(hotkey)
        case .trigger(.tap), .trigger(.doubleTap): return .hint(.needsModifierTap)
        case .trigger(.combo): return hotkey.keepsItsCharacter ? .hint(.missingModifier) : .capture(hotkey)
        }
    }

    /// A modifier pressed on its own, once or twice: recorded when that is the kind wanted,
    /// otherwise nothing — while recording a combo it is a combo begun and abandoned.
    public static func outcome(of tap: ModifierTapEvent, recording target: RecorderTarget) -> RecorderKeyOutcome? {
        switch (tap, target) {
        case (.tap, .trigger(.tap)), (.doubleTap, .trigger(.doubleTap)): .captureTap(tap)
        default: nil
        }
    }

    /// The recognizer a recorder judges taps with while recording `target`: every key counts as
    /// bound the way being recorded, so a double tap needs its second tap and a tap needn't wait.
    public static func tapRecognizer(recording target: RecorderTarget) -> TriggerTapRecognizer {
        var recognizer = TriggerTapRecognizer()
        let everyKey = Set(ModifierKey.allCases)
        switch target {
        case .trigger(.tap): recognizer.tapKeys = everyKey
        case .trigger(.doubleTap): recognizer.doubleTapKeys = everyKey
        case .trigger(.combo), .pageKeystroke: break
        }
        return recognizer
    }
}
