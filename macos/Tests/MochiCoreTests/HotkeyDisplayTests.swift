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

    /// #112: the F-keys have names — ⇧ plus an F-key is a valid trigger (ADR-0023), so one is
    /// recorded, shown in the tray and on the Empty Page, never as "Key 96". Keycodes are
    /// `kVK_F1` … `kVK_F20` from Carbon's Events.h, which are not in order.
    @Test(arguments: [
        (keyCode: UInt32(0x7A), name: "F1"), (keyCode: 0x78, name: "F2"), (keyCode: 0x63, name: "F3"),
        (keyCode: 0x76, name: "F4"), (keyCode: 0x60, name: "F5"), (keyCode: 0x61, name: "F6"),
        (keyCode: 0x62, name: "F7"), (keyCode: 0x64, name: "F8"), (keyCode: 0x65, name: "F9"),
        (keyCode: 0x6D, name: "F10"), (keyCode: 0x67, name: "F11"), (keyCode: 0x6F, name: "F12"),
        (keyCode: 0x69, name: "F13"), (keyCode: 0x6B, name: "F14"), (keyCode: 0x71, name: "F15"),
        (keyCode: 0x6A, name: "F16"), (keyCode: 0x40, name: "F17"), (keyCode: 0x4F, name: "F18"),
        (keyCode: 0x50, name: "F19"), (keyCode: 0x5A, name: "F20"),
    ])
    func describesTheFunctionKeys(_ row: (keyCode: UInt32, name: String)) {
        let shifted = Hotkey(keyCode: row.keyCode, modifierFlags: 0x0200)
        #expect(HotkeyDisplay.describe(Hotkey(keyCode: row.keyCode, modifierFlags: 0)) == row.name)
        #expect(HotkeyDisplay.describe(shifted) == "⇧\(row.name)")
        #expect(HotkeyDisplay.keys(of: shifted) == ["⇧", row.name])
        #expect(HotkeyDisplay.describe(TriggerKey.keystroke(shifted)) == "⇧\(row.name)")
        // The F-keys are exactly the keys ⇧ alone may go with.
        #expect(!shifted.isMissingModifier)
    }

    @Test func describesFunctionKeysWithOtherModifiers() {
        #expect(HotkeyDisplay.describe(Hotkey(keyCode: 0x60, modifierFlags: 0x0800 | 0x0200)) == "⌥⇧F5")
        #expect(HotkeyDisplay.describe(Hotkey(keyCode: 0x6F, modifierFlags: 0x1000)) == "⌃F12")
    }

    /// The tray draws an F-key hint with AppKit's function-key characters, `NSF1FunctionKey`
    /// (U+F704) … `NSF20FunctionKey` (U+F717), not with its two-letter name.
    @Test func menuKeyEquivalentOfAFunctionKeyIsAppKitsFunctionKeyCharacter() {
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 0x7A, modifierFlags: 0x0200)) == "\u{F704}")
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 0x60, modifierFlags: 0x0200)) == "\u{F708}")
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 0x5A, modifierFlags: 0)) == "\u{F717}")
    }

    @Test func fallsBackToANumericLabelForAnUnmappedKeyCode() {
        let hotkey = Hotkey(keyCode: 999, modifierFlags: 0)
        #expect(HotkeyDisplay.describe(hotkey) == "Key 999")
    }

    // #63: the tray draws its hints in the menu's key-equivalent column.

    /// Lowercase, because an uppercase key equivalent means "with ⇧" to AppKit — ⌥G would come
    /// out as ⌥⇧G.
    @Test func menuKeyEquivalentOfALetterIsLowercase() {
        #expect(HotkeyDisplay.menuKeyEquivalent(for: DefaultHotkeys.toggleGhostMode) == "g")
        #expect(HotkeyDisplay.menuKeyEquivalent(for: DefaultHotkeys.quit) == "q")
    }

    @Test func menuKeyEquivalentOfPunctuationAndNamedKeysIsTheCharacterItself() {
        #expect(HotkeyDisplay.menuKeyEquivalent(for: DefaultHotkeys.openSettings) == ",")
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 0x31, modifierFlags: 0)) == " ")
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 0x24, modifierFlags: 0)) == "\r")
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 0x7E, modifierFlags: 0)) == "\u{F700}")
    }

    @Test func menuKeyEquivalentIsNilForAnUnmappedKeyCode() {
        #expect(HotkeyDisplay.menuKeyEquivalent(for: Hotkey(keyCode: 999, modifierFlags: 0)) == nil)
    }
    // MARK: 视频控制 (#74)

    @Test(arguments: [
        (key: ModifierKey.rightOption, expected: "右 ⌥"),
        (key: .leftOption, expected: "左 ⌥"),
        (key: .rightCommand, expected: "右 ⌘"),
        (key: .leftCommand, expected: "左 ⌘"),
        (key: .rightShift, expected: "右 ⇧"),
        (key: .leftShift, expected: "左 ⇧"),
        (key: .rightControl, expected: "右 ⌃"),
        (key: .leftControl, expected: "左 ⌃"),
    ])
    func describesAModifierTapByItsSide(_ testCase: (key: ModifierKey, expected: String)) {
        #expect(HotkeyDisplay.describe(.modifierTap(testCase.key)) == testCase.expected)
        #expect(HotkeyDisplay.keys(of: .modifierTap(testCase.key)) == [testCase.expected])
    }

    @Test func describesAKeystrokeTriggerLikeTheHotkeyItWraps() {
        let backtick = Hotkey(keyCode: 0x32, modifierFlags: 0)
        #expect(HotkeyDisplay.describe(.keystroke(backtick)) == "`")
        #expect(HotkeyDisplay.keys(of: .keystroke(Hotkey(keyCode: 0x26, modifierFlags: 0x0800))) == ["⌥", "J"])
    }

    // MARK: #91 连按两次

    @Test func aDoubleTapReadsAsItsKeyMarkedTimesTwo() {
        #expect(HotkeyDisplay.describe(.modifierDoubleTap(.rightOption)) == "右 ⌥ ×2")
        #expect(HotkeyDisplay.keys(of: .modifierDoubleTap(.rightOption)) == ["右 ⌥"])
    }

    /// The quick reference draws the key once, as a keycap, and the "×2" beside it — not as a
    /// second keycap, which would read as two different keys.
    @Test func theQuickReferenceMarksADoubleTapRatherThanDrawingItsKeyTwice() {
        let config = WidgetConfig().updatingVideoControlTrigger(.modifierDoubleTap(.rightOption), for: .seekForward)

        let entries = HotkeyQuickReference.entries(for: config)

        let forward = entries.first { $0.label.hasPrefix("前进") }
        #expect(forward?.keys == ["右 ⌥"])
        #expect(forward?.mark == "×2")
        #expect(entries.first { $0.label.hasPrefix("播放/暂停") }?.mark == nil)
    }
}
