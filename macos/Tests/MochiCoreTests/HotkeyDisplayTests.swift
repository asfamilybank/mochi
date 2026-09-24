import Testing

@testable import MochiCore

@Suite struct HotkeyDisplayTests {
    @Test func describesModifiersInFixedControlOptionShiftCommandOrder() {
        let hotkey = Hotkey(keyCode: 0x05, modifierFlags: 0x0100 | 0x0800)
        #expect(HotkeyDisplay.describe(hotkey) == "⌥⌘G")
    }

    /// #58: the defaults moved off ⌥⌘ onto a bare ⌥, so ⌥⌘H (隐藏其他) goes back to macOS.
    @Test func describesTheDefaultActionHotkeysAsOptionOnlyCombos() {
        #expect(HotkeyDisplay.describe(DefaultHotkeys.toggleGhostMode) == "⌥G")
        #expect(HotkeyDisplay.describe(DefaultHotkeys.hideWidget) == "⌥H")
        #expect(HotkeyDisplay.keys(of: DefaultHotkeys.hideWidget) == ["⌥", "H"])
    }

    @Test func describesAllFourModifiersTogether() {
        let hotkey = Hotkey(keyCode: 0x00, modifierFlags: 0x1000 | 0x0800 | 0x0200 | 0x0100)
        #expect(HotkeyDisplay.describe(hotkey) == "⌃⌥⇧⌘A")
    }

    @Test func describesAKeyWithNoModifiers() {
        let hotkey = Hotkey(keyCode: 0x31, modifierFlags: 0)
        #expect(HotkeyDisplay.describe(hotkey) == "Space")
    }

    /// ⌘, is on the Empty Page's quick reference, so the comma needs a glyph of its own.
    @Test func describesTheSettingsShortcut() {
        #expect(HotkeyDisplay.describe(DefaultHotkeys.openSettings) == "⌘,")
    }

    /// ⌘. (#60) is reserved, so a mapping conflict with it must read as "⌘.", not a key code.
    @Test func describesTheStopShortcutAndKeepsItReserved() {
        let stop = Hotkey(keyCode: 0x2F, modifierFlags: 0x0100)
        #expect(HotkeyDisplay.describe(stop) == "⌘.")
        #expect(DefaultHotkeys.reservedLocalMenuShortcuts.contains(stop))
    }

    @Test func splitsAComboIntoOneGlyphPerKeyInTheSameOrder() {
        let hotkey = Hotkey(keyCode: 0x0B, modifierFlags: 0x0200 | 0x0100)
        #expect(HotkeyDisplay.keys(of: hotkey) == ["⇧", "⌘", "B"])
        #expect(HotkeyDisplay.keys(of: Hotkey(keyCode: 0x31, modifierFlags: 0)) == ["Space"])
    }

    @Test func fallsBackToANumericLabelForAnUnmappedKeyCode() {
        let hotkey = Hotkey(keyCode: 999, modifierFlags: 0)
        #expect(HotkeyDisplay.describe(hotkey) == "Key 999")
    }
}
