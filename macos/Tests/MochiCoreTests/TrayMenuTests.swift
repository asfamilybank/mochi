import AppKit
import Testing

@testable import MochiCore

/// The AppKit side of the tray menu (#63): closures re-read on every open, hints drawn in the
/// key-equivalent column but never offered for matching. Icons are left out (`nil`/`.appQuit`)
/// on purpose — the ghost renders through `NSFont`, which only the serialized metrics suite may
/// touch (see `CLAUDE.md` on concurrent `NSFont.systemFont` calls).
@Suite struct TrayMenuTests {
    @Test func hintsChecksAndSeparatorsFollowTheClosuresEachTimeTheMenuOpens() {
        var hint: Hotkey? = DefaultHotkeys.toggleGhostMode
        var checked = false
        let tray = TrayMenu(items: [
            TrayMenuItem(title: "幽灵模式", hotkeyHint: { hint }, isChecked: { checked }) {},
            .separator,
            TrayMenuItem(title: "退出", icon: .appQuit, hotkeyHint: { DefaultHotkeys.quit }) {},
        ])
        let items = tray.menu.items

        #expect(items.map(\.isSeparatorItem) == [false, true, false])
        #expect(items[0].keyEquivalent == "g")
        #expect(items[0].keyEquivalentModifierMask == [.option])
        #expect(items[0].state == .off)
        #expect(items[2].keyEquivalent == "q")
        #expect(items[2].keyEquivalentModifierMask == [.command])
        #expect(items[2].action == #selector(NSApplication.terminate(_:)))

        hint = Hotkey(keyCode: 0x0E, modifierFlags: 0x1000 | 0x0200)  // ⌃⇧E
        checked = true
        tray.menuNeedsUpdate(tray.menu)

        #expect(items[0].keyEquivalent == "e")
        #expect(items[0].keyEquivalentModifierMask == [.control, .shift])
        #expect(items[0].state == .on)

        hint = nil
        tray.menuNeedsUpdate(tray.menu)

        #expect(items[0].keyEquivalent == "")
    }

    /// With the menu closed, AppKit must never find a hint to match — the Carbon hotkey is the
    /// only keyboard path to these actions.
    @Test func neverOffersItsHintsForKeyEquivalentMatching() throws {
        let tray = TrayMenu(items: [
            TrayMenuItem(title: "幽灵模式", hotkeyHint: { DefaultHotkeys.toggleGhostMode }) {},
        ])
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0, windowNumber: 0,
            context: nil, characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: 0x05))
        var target: AnyObject?
        var action: Selector?

        #expect(!tray.menuHasKeyEquivalent(tray.menu, for: event, target: &target, action: &action))
    }

    /// Only a keypress that *is* the item's hint is dropped (the Carbon hotkey owns that combo) —
    /// choosing an item from the keyboard (arrows + Return) must still run it (code review, #63).
    @Test(arguments: [
        (keyCode: UInt16(0x05), modifiers: NSEvent.ModifierFlags.option.rawValue, hasHint: true, ignored: true),
        (keyCode: 0x24, modifiers: 0, hasHint: true, ignored: false),  // Return
        (keyCode: 0x31, modifiers: 0, hasHint: true, ignored: false),  // Space
        (keyCode: 0x05, modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue, hasHint: true, ignored: false),
        (keyCode: 0x24, modifiers: 0, hasHint: false, ignored: false),
    ])
    func dropsOnlyTheKeypressThatMatchesTheItemsHint(
        _ row: (keyCode: UInt16, modifiers: UInt, hasHint: Bool, ignored: Bool)
    ) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: row.modifiers),
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: row.keyCode))
        let hint = row.hasHint ? DefaultHotkeys.toggleGhostMode : nil  // ⌥G

        #expect(TrayMenu.isHintKeypress(event, hint: hint) == row.ignored)
    }

    @Test func aClickIsNeverTakenForAHintKeypress() throws {
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [.option], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0))

        #expect(!TrayMenu.isHintKeypress(click, hint: DefaultHotkeys.toggleGhostMode))
        #expect(!TrayMenu.isHintKeypress(nil, hint: DefaultHotkeys.toggleGhostMode))
    }
}
