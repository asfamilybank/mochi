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

extension RawInputEvent {
    public var timestamp: TimeInterval {
        switch self {
        case .modifierChanged(_, _, _, let timestamp), .keyDown(_, _, _, let timestamp), .mouseDown(let timestamp):
            timestamp
        }
    }
}

/// A modifier pressed on its own, once or twice (#91).
public enum ModifierTapEvent: Equatable, Sendable {
    case tap(ModifierKey)
    case doubleTap(ModifierKey)

    public var trigger: TriggerKey {
        switch self {
        case .tap(let key): .modifierTap(key)
        case .doubleTap(let key): .modifierDoubleTap(key)
        }
    }
}

/// Turns taps into taps and double taps (#91, ADR-0022), given which keys are bound which way:
///
/// - a key bound to a double tap remembers its tap; the same key tapped again within
///   `doubleTapInterval` (release to release) is a double tap;
/// - a key bound **both** ways holds its tap back until that interval has passed —
///   `releaseHeldBackTap()`, called by whoever keeps the time, turns it into a tap then — so a
///   double tap never also fires the tap;
/// - every other key's tap is a tap at once, so binding a double tap somewhere never slows the
///   default 播放/暂停 down.
///
/// Anything else pressed in between — a key, a mouse button, another modifier — ends the sequence
/// and drops a held-back tap, the same rule a single tap already follows.
public struct TriggerTapRecognizer {
    public static let doubleTapInterval: TimeInterval = 0.3

    /// The keys bound to a tap and to a double tap; set before each event.
    public var tapKeys: Set<ModifierKey> = []
    public var doubleTapKeys: Set<ModifierKey> = []

    /// A tap waiting out the double-tap interval.
    public struct HeldBackTap: Equatable, Sendable {
        public var key: ModifierKey
        public var at: TimeInterval
    }

    public private(set) var heldBackTap: HeldBackTap?
    private var taps = ModifierTapRecognizer()
    private var firstTap: (key: ModifierKey, at: TimeInterval)?

    public init() {}

    public mutating func handle(_ event: RawInputEvent) -> [ModifierTapEvent] {
        guard let key = taps.handle(event) else {
            if !isSecondPress(event) {
                firstTap = nil
                heldBackTap = nil
            }
            return []
        }
        let time = event.timestamp
        if let firstTap, firstTap.key == key, time - firstTap.at <= Self.doubleTapInterval {
            self.firstTap = nil
            heldBackTap = nil
            return [.doubleTap(key)]
        }
        // A held-back tap whose interval ran out before its release was delivered is still a tap.
        let overdue = heldBackTap.map { [ModifierTapEvent.tap($0.key)] } ?? []
        heldBackTap = nil
        guard doubleTapKeys.contains(key) else {
            firstTap = nil
            return overdue + [.tap(key)]
        }
        firstTap = (key, time)
        if tapKeys.contains(key) { heldBackTap = HeldBackTap(key: key, at: time) }
        return overdue
    }

    /// The double-tap interval passed with no second tap: the held-back tap, a tap after all.
    public mutating func releaseHeldBackTap() -> ModifierTapEvent? {
        defer {
            heldBackTap = nil
            firstTap = nil
        }
        return heldBackTap.map { .tap($0.key) }
    }

    /// The same modifier going down again, alone — the start of the second tap, which mustn't
    /// end the sequence it completes.
    private func isSecondPress(_ event: RawInputEvent) -> Bool {
        guard let firstTap, case .modifierChanged(let keyCode, let held, _, _) = event else { return false }
        return keyCode == firstTap.key.keyCode && held == [firstTap.key]
    }
}

/// A control that is capturing keys for itself — the settings panel's recorders (#79). While one
/// is first responder and capturing, 视频控制 ignores Mochi's own input, so recording right ⌥
/// doesn't also pause the video.
public protocol KeyCapturingResponder: AnyObject {
    var isCapturingKeys: Bool { get }
}
