import Testing

@testable import MochiCore

/// #82: what the settings panel's recorder field shows, and what a key pressed while it records
/// means — shared by every recorder, so the two kinds can't drift apart.
@Suite struct HotkeyRecorderModelTests {
    // MARK: - Face

    @Test(arguments: [
        (modifiers: UInt32(0x0800), lit: [ModifierSlot.option], key: "G"),
        (modifiers: UInt32(0x1000 | 0x0200), lit: [ModifierSlot.control, .shift], key: "G"),
        (modifiers: UInt32(0x1000 | 0x0800 | 0x0200 | 0x0100), lit: [ModifierSlot.control, .option, .shift, .command], key: "G"),
        (modifiers: UInt32(0), lit: [ModifierSlot](), key: "G"),
    ])
    func aComboLightsExactlyItsModifierSlots(_ c: (modifiers: UInt32, lit: [ModifierSlot], key: String)) {
        let face = HotkeyRecorderModel.face(of: Hotkey(keyCode: 0x05, modifierFlags: c.modifiers) as Hotkey?)
        #expect(face == .slots(lit: Set(c.lit), key: c.key))
    }

    @Test func nothingBoundShowsEveryModifierSlotDimAndNoKey() {
        #expect(HotkeyRecorderModel.face(of: nil as Hotkey?) == .slots(lit: [], key: nil))
        #expect(HotkeyRecorderModel.face(of: nil as VideoControlTrigger?) == .slots(lit: [], key: nil))
    }

    @Test func theSlotsReadInTheFixedControlOptionShiftCommandOrder() {
        #expect(ModifierSlot.allCases.map(\.glyph) == ["⌃", "⌥", "⇧", "⌘"])
    }

    /// A tapped modifier is pressed on its own — lighting the ⌥ slot would read as "⌥ plus some key".
    @Test func aModifierTapIsOneCapNamingItsSide() {
        #expect(HotkeyRecorderModel.face(of: VideoControlTrigger.modifierTap(.rightOption) as VideoControlTrigger?)
            == .singleCap("右 ⌥"))
    }

    @Test func aVideoKeystrokeReadsLikeAnyOtherCombo() {
        let trigger = VideoControlTrigger.keystroke(Hotkey(keyCode: 0x7B, modifierFlags: 0x0100))
        #expect(HotkeyRecorderModel.face(of: trigger as VideoControlTrigger?) == .slots(lit: [.command], key: "←"))
    }

    // MARK: - Keys pressed while recording

    @Test(arguments: [
        (keyCode: UInt32(0x35), outcome: RecorderKeyOutcome.cancel),  // Esc
        (keyCode: UInt32(0x33), outcome: RecorderKeyOutcome.clear),  // ⌫
        (keyCode: UInt32(0x75), outcome: RecorderKeyOutcome.clear),  // ⌦
    ])
    func aBareEscapeCancelsAndABareDeleteClears(_ c: (keyCode: UInt32, outcome: RecorderKeyOutcome)) {
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: c.keyCode, modifierFlags: 0) == c.outcome)
    }

    /// Only the bare keys are taken over — ⌥⌫ or ⌘Esc are still keys a user can bind.
    @Test(arguments: [UInt32(0x35), 0x33, 0x75])
    func theSameKeysWithAModifierAreRecorded(keyCode: UInt32) {
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: keyCode, modifierFlags: 0x0800)
            == .capture(Hotkey(keyCode: keyCode, modifierFlags: 0x0800)))
    }

    @Test func anyOtherKeyIsRecorded() {
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: 0x05, modifierFlags: 0)
            == .capture(Hotkey(keyCode: 0x05, modifierFlags: 0)))
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: 0x05, modifierFlags: 0x0800)
            == .capture(Hotkey(keyCode: 0x05, modifierFlags: 0x0800)))
    }
}
