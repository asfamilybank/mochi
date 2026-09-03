import AppKit
import MochiCore
import SwiftUI

/// Records a single keystroke (key code + Carbon-style modifier flags) for the hotkey mapping
/// editor (#14): click to focus, then press the desired combo. A raw `keyDown` capture rather
/// than a text field, since typing a keyCode/modifier bitmask by hand isn't something a user
/// should ever have to do.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: Hotkey?
    var placeholder: String

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let view = HotkeyRecorderButton()
        view.onCapture = { hotkey = $0 }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderButton, context: Context) {
        nsView.placeholder = placeholder
        nsView.displayedHotkey = hotkey
    }
}

final class HotkeyRecorderButton: NSButton {
    var placeholder: String = "点击录制" { didSet { refreshTitle() } }
    var displayedHotkey: Hotkey? { didSet { refreshTitle() } }
    var onCapture: ((Hotkey) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        title = "按下组合键…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        isRecording = false
        let hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifierFlags: Self.carbonModifiers(from: event.modifierFlags))
        displayedHotkey = hotkey
        onCapture?(hotkey)
    }

    private func refreshTitle() {
        guard !isRecording else { return }
        title = displayedHotkey.map(HotkeyDisplay.describe) ?? placeholder
    }

    /// Translates AppKit's `NSEvent.ModifierFlags` into the Carbon-style bitmask `Hotkey`/
    /// `GlobalHotkeyRegistry` use everywhere else in the codebase (`0x0100`=cmd, `0x0200`=shift,
    /// `0x0800`=option, `0x1000`=control — see `Hotkey.swift`'s `DefaultHotkeys.cmdOption`).
    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= 0x0100 }
        if flags.contains(.shift) { result |= 0x0200 }
        if flags.contains(.option) { result |= 0x0800 }
        if flags.contains(.control) { result |= 0x1000 }
        return result
    }
}
