import Foundation

/// One user-configured "trigger key → page keystroke" pairing driving Hotkey Forwarding (#11,
/// ADR-0003): pressing `trigger` while Ghost Mode is active injects `pageKeystroke` into the
/// widget's page via `CGEventPostToPid`, indistinguishable from the user having pressed
/// `pageKeystroke` themselves. `AppKitPlatformOps` re-interprets `pageKeystroke`'s flags as
/// `CGEventFlags` instead of Carbon's bit values when actually injecting it.
///
/// A combo trigger is a Carbon global hotkey, taken from every app; a tap or double tap (#92,
/// ADR-0022) is only listened for, alongside 视频控制, and takes nothing.
public struct HotkeyMapping: Equatable, Sendable {
    public var trigger: TriggerKey
    public var pageKeystroke: Hotkey

    public init(trigger: TriggerKey, pageKeystroke: Hotkey) {
        self.trigger = trigger
        self.pageKeystroke = pageKeystroke
    }

    /// A combo-triggered mapping — every mapping before #92.
    public init(trigger: Hotkey, pageKeystroke: Hotkey) {
        self.init(trigger: .keystroke(trigger), pageKeystroke: pageKeystroke)
    }

    /// The combo Carbon holds for this mapping; `nil` for a tap or double tap, which it doesn't.
    public var registeredHotkey: Hotkey? {
        if case .keystroke(let hotkey) = trigger { hotkey } else { nil }
    }
}
