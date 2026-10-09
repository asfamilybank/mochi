import Foundation

/// One side of one modifier key — 视频控制 (#74) tells right ⌥ from left ⌥, which a Carbon
/// hotkey's modifier mask cannot. Identified by the physical key code (`kVK_*`), so neither the
/// keyboard layout nor the input method changes which key it is.
public enum ModifierKey: String, CaseIterable, Hashable, Sendable {
    case leftCommand = "left_command"
    case rightCommand = "right_command"
    case leftOption = "left_option"
    case rightOption = "right_option"
    case leftShift = "left_shift"
    case rightShift = "right_shift"
    case leftControl = "left_control"
    case rightControl = "right_control"

    public var keyCode: UInt16 {
        switch self {
        case .leftCommand: 0x37   // kVK_Command
        case .rightCommand: 0x36  // kVK_RightCommand
        case .leftOption: 0x3A    // kVK_Option
        case .rightOption: 0x3D   // kVK_RightOption
        case .leftShift: 0x38     // kVK_Shift
        case .rightShift: 0x3C    // kVK_RightShift
        case .leftControl: 0x3B   // kVK_Control
        case .rightControl: 0x3E  // kVK_RightControl
        }
    }

    public init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }
}

/// What the platform reports while 视频控制 is listening (#74) — raw and listen-only: every event
/// still reaches whichever app it was meant for. Deciding what counts as a tap is MochiCore's job
/// (`ModifierTapRecognizer`), so the platform layer stays a plain pipe.
public enum RawInputEvent: Equatable, Sendable {
    /// A modifier-type key went down or up. `keyCode` is the key that changed — also Caps Lock or
    /// fn, which no `ModifierKey` names; `held` is every side-specific modifier down *after* it.
    /// `lastPressAt` is when the system last saw any key or mouse button go down, on the same
    /// clock as `timestamp` — including presses no listener ever sees, because a hotkey (Mochi's
    /// own ⌥H) or a system shortcut (⌘Tab) swallowed them, or Secure Input hid them.
    case modifierChanged(keyCode: UInt16, held: Set<ModifierKey>, lastPressAt: TimeInterval, timestamp: TimeInterval)
    /// An ordinary key went down. `modifierFlags` uses `Hotkey`'s Carbon bit values.
    case keyDown(keyCode: UInt32, modifierFlags: UInt32, isRepeat: Bool, timestamp: TimeInterval)
    /// Any mouse button went down.
    case mouseDown(timestamp: TimeInterval)
}

/// Turns raw modifier changes into taps (#74): a side-specific modifier pressed on its own and
/// released within `maxHoldDuration`, with no other key, mouse button or modifier in between. It
/// fires on release — the only moment "nothing else joined in" is known. A key in between that the
/// listener never saw still counts: the system's last press is then later than the modifier's.
public struct ModifierTapRecognizer {
    /// Holding longer than this is a held modifier the user changed their mind about, not a tap.
    public static let maxHoldDuration: TimeInterval = 0.5

    private var pending: (key: ModifierKey, pressedAt: TimeInterval)?

    public init() {}

    /// Feeds one event in; returns the tapped key when this event completes a tap.
    public mutating func handle(_ event: RawInputEvent) -> ModifierKey? {
        guard case .modifierChanged(let keyCode, let held, let lastPressAt, let timestamp) = event,
              let key = ModifierKey(keyCode: keyCode)
        else {
            pending = nil
            return nil
        }
        if held.contains(key) {
            pending = held == [key] ? (key, timestamp) : nil
            return nil
        }
        defer { pending = nil }
        // Compared as event times, not as counts read when each event is handled: the listener can
        // lag, and by then a key typed in between may already be on both sides of the count.
        guard let pending, pending.key == key, held.isEmpty, lastPressAt <= pending.pressedAt,
              timestamp - pending.pressedAt <= Self.maxHoldDuration
        else { return nil }
        return key
    }
}

/// A control that is capturing keys for itself — the settings panel's recorders (#79). While one
/// is first responder and capturing, 视频控制 ignores Mochi's own input, so recording right ⌥
/// doesn't also pause the video.
public protocol KeyCapturingResponder: AnyObject {
    var isCapturingKeys: Bool { get }
}
