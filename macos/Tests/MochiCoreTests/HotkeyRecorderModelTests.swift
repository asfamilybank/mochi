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

    private static let everyTarget: [RecorderTarget] = [.trigger(.tap), .trigger(.combo), .pageKeystroke]

    /// Esc and ⌫/⌦ mean the same whatever is being recorded.
    @Test(arguments: everyTarget)
    func aBareEscapeCancelsAndABareDeleteClears(_ target: RecorderTarget) {
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: 0x35, modifierFlags: 0, recording: target) == .cancel)
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: 0x33, modifierFlags: 0, recording: target) == .clear)
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: 0x75, modifierFlags: 0, recording: target) == .clear)
    }

    /// Only the bare keys are taken over — ⌥⌫ or ⌘Esc are still keys a user can bind.
    @Test(arguments: [UInt32(0x35), 0x33, 0x75])
    func theSameKeysWithAModifierAreRecorded(keyCode: UInt32) {
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: keyCode, modifierFlags: 0x0800, recording: .trigger(.combo))
            == .capture(Hotkey(keyCode: keyCode, modifierFlags: 0x0800)))
    }

    /// #90 + #89: what a key pressed while recording means depends on what is being recorded.
    @Test(arguments: [
        (target: RecorderTarget.trigger(.combo), modifiers: UInt32(0x0800), outcome: RecorderKeyOutcome.capture(Hotkey(keyCode: 0x26, modifierFlags: 0x0800))),
        (target: .trigger(.combo), modifiers: UInt32(0), outcome: .hint(.missingModifier)),
        (target: .trigger(.combo), modifiers: UInt32(0x0200), outcome: .hint(.missingModifier)),
        (target: .trigger(.tap), modifiers: UInt32(0), outcome: .hint(.needsModifierTap)),
        (target: .trigger(.tap), modifiers: UInt32(0x0800), outcome: .hint(.needsModifierTap)),
        (target: .pageKeystroke, modifiers: UInt32(0), outcome: .capture(Hotkey(keyCode: 0x26, modifierFlags: 0))),
        (target: .pageKeystroke, modifiers: UInt32(0x0200), outcome: .capture(Hotkey(keyCode: 0x26, modifierFlags: 0x0200))),
    ])
    func aKeyIsRecordedOnlyWhenItFitsWhatIsBeingRecorded(_ c: (target: RecorderTarget, modifiers: UInt32, outcome: RecorderKeyOutcome)) {
        #expect(HotkeyRecorderModel.outcome(ofKeyDown: 0x26, modifierFlags: c.modifiers, recording: c.target) == c.outcome)
    }

    /// A modifier tapped on its own records only when a tap is what is being recorded; while a
    /// combo is, it is just the start of one the user changed their mind about.
    @Test(arguments: [
        (target: RecorderTarget.trigger(.tap), outcome: RecorderKeyOutcome?.some(.captureTap(.rightOption))),
        (target: .trigger(.combo), outcome: nil),
        (target: .pageKeystroke, outcome: nil),
    ])
    func aModifierTapIsRecordedOnlyAsATap(_ c: (target: RecorderTarget, outcome: RecorderKeyOutcome?)) {
        #expect(HotkeyRecorderModel.outcome(ofModifierTap: .rightOption, recording: c.target) == c.outcome)
    }

    @Test func aVideoKeyIsOfTheKindItWasRecordedAs() {
        #expect(VideoControlTrigger.modifierTap(.rightOption).kind == .tap)
        #expect(VideoControlTrigger.keystroke(Hotkey(keyCode: 0x26, modifierFlags: 0x0800)).kind == .combo)
    }
}
