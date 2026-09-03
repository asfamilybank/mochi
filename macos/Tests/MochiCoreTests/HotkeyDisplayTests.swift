import Testing

@testable import MochiCore

@Suite struct HotkeyDisplayTests {
    @Test func describesModifiersInFixedControlOptionShiftCommandOrder() {
        let hotkey = Hotkey(keyCode: 0x05, modifierFlags: 0x0100 | 0x0800)
        #expect(HotkeyDisplay.describe(hotkey) == "⌥⌘G")
    }

    @Test func describesAllFourModifiersTogether() {
        let hotkey = Hotkey(keyCode: 0x00, modifierFlags: 0x1000 | 0x0800 | 0x0200 | 0x0100)
        #expect(HotkeyDisplay.describe(hotkey) == "⌃⌥⇧⌘A")
    }

    @Test func describesAKeyWithNoModifiers() {
        let hotkey = Hotkey(keyCode: 0x31, modifierFlags: 0)
        #expect(HotkeyDisplay.describe(hotkey) == "Space")
    }

    @Test func fallsBackToANumericLabelForAnUnmappedKeyCode() {
        let hotkey = Hotkey(keyCode: 999, modifierFlags: 0)
        #expect(HotkeyDisplay.describe(hotkey) == "Key 999")
    }
}
