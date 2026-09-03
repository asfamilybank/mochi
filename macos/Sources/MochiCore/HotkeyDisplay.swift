import Foundation

/// Renders a `Hotkey` as a human-readable label (e.g. "⌥⌘G") for the hotkey mapping editor
/// (#14) — `Hotkey` itself only stores a raw virtual keycode + Carbon modifier bitmask, neither of
/// which is fit to show a user directly.
public enum HotkeyDisplay {
    /// Modifier glyphs in the fixed left-to-right order macOS itself uses (⌃⌥⇧⌘), independent of
    /// which bits happen to be set.
    public static func describe(_ hotkey: Hotkey) -> String {
        modifierGlyphs(for: hotkey.modifierFlags) + keyGlyph(for: hotkey.keyCode)
    }

    private static func modifierGlyphs(for modifierFlags: UInt32) -> String {
        var glyphs = ""
        if modifierFlags & 0x1000 != 0 { glyphs += "⌃" }
        if modifierFlags & 0x0800 != 0 { glyphs += "⌥" }
        if modifierFlags & 0x0200 != 0 { glyphs += "⇧" }
        if modifierFlags & 0x0100 != 0 { glyphs += "⌘" }
        return glyphs
    }

    /// Covers the common ANSI virtual keycodes (letters, digits, a handful of named keys) a user
    /// is realistically going to pick for a mapping; anything else falls back to a numeric label
    /// rather than guessing at a glyph.
    private static func keyGlyph(for keyCode: UInt32) -> String {
        keyGlyphsByCode[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyGlyphsByCode: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
        0x31: "Space", 0x24: "Return", 0x30: "Tab", 0x33: "Delete", 0x35: "Esc",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x18: "=", 0x1B: "-",
    ]
}
