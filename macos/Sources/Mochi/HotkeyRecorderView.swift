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

final class HotkeyRecorderButton: NSButton, KeyCapturingResponder {
    var placeholder: String = "点击录制" { didSet { refreshTitle() } }
    var displayedHotkey: Hotkey? { didSet { refreshTitle() } }
    var onCapture: ((Hotkey) -> Void)?
    private var isRecording = false
    var isCapturingKeys: Bool { isRecording }

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

/// Records a 视频控制 key (#79): either a modifier tapped on its own — judged by the same
/// `ModifierTapRecognizer` that listens in Ghost Mode, so what records is exactly what fires — or
/// an ordinary key or combo, taken on key-down. Esc cancels.
struct VideoControlRecorderView: NSViewRepresentable {
    @Binding var trigger: VideoControlTrigger?
    var placeholder: String

    func makeNSView(context: Context) -> VideoControlRecorderButton {
        let view = VideoControlRecorderButton()
        view.onCapture = { trigger = $0 }
        return view
    }

    func updateNSView(_ nsView: VideoControlRecorderButton, context: Context) {
        nsView.placeholder = placeholder
        nsView.displayedTrigger = trigger
    }
}

final class VideoControlRecorderButton: NSButton, KeyCapturingResponder {
    var placeholder: String = "未设置" { didSet { refreshTitle() } }
    var displayedTrigger: VideoControlTrigger? { didSet { refreshTitle() } }
    var onCapture: ((VideoControlTrigger) -> Void)?
    private(set) var isCapturingKeys = false
    private var tapRecognizer = ModifierTapRecognizer()

    private static let escapeKeyCode: UInt32 = 0x35

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
        isCapturingKeys = true
        tapRecognizer = ModifierTapRecognizer()
        title = "按下按键，或单独轻按修饰键…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturingKeys, let raw = RawInputEvent(event),
              case .keyDown(let keyCode, let modifierFlags, _, _) = raw
        else {
            super.keyDown(with: event)
            return
        }
        _ = tapRecognizer.handle(raw)
        if keyCode == Self.escapeKeyCode, modifierFlags == 0 {
            stopRecording()
            return
        }
        finish(with: .keystroke(Hotkey(keyCode: keyCode, modifierFlags: modifierFlags)))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturingKeys, let raw = RawInputEvent(event) else {
            super.flagsChanged(with: event)
            return
        }
        if let tapped = tapRecognizer.handle(raw) {
            finish(with: .modifierTap(tapped))
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func finish(with trigger: VideoControlTrigger) {
        stopRecording()
        displayedTrigger = trigger
        onCapture?(trigger)
    }

    private func stopRecording() {
        isCapturingKeys = false
        refreshTitle()
    }

    private func refreshTitle() {
        guard !isCapturingKeys else { return }
        title = displayedTrigger.map(HotkeyDisplay.describe) ?? placeholder
    }
}
