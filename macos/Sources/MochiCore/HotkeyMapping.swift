import Foundation

/// One user-configured "global hotkey → page keystroke" pairing driving Hotkey Forwarding (#11,
/// ADR-0003): pressing `trigger` while Ghost Mode is active injects `pageKeystroke` into the
/// widget's page via `CGEventPostToPid`, indistinguishable from the user having pressed
/// `pageKeystroke` themselves. Reuses `Hotkey`'s keyCode+modifierFlags shape for both sides rather
/// than introducing a near-identical second type — `AppKitPlatformOps` is responsible for
/// re-interpreting `pageKeystroke`'s flags as `CGEventFlags` instead of Carbon's bit values when
/// actually injecting it.
public struct HotkeyMapping: Equatable {
    public var trigger: Hotkey
    public var pageKeystroke: Hotkey

    public init(trigger: Hotkey, pageKeystroke: Hotkey) {
        self.trigger = trigger
        self.pageKeystroke = pageKeystroke
    }
}
