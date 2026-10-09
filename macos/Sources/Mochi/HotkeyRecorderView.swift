import AppKit
import MochiCore
import SwiftUI

/// Records a single keystroke (key code + Carbon-style modifier flags): the action hotkeys and
/// the forwarding mappings. A raw `keyDown` capture rather than a text field, since typing a
/// keyCode/modifier bitmask by hand isn't something a user should ever have to do.
///
/// `onClear` is the field's ⓧ (and ⌫ while recording); `nil` leaves the binding unclearable.
///
/// `isRecordable: false` is the read-only form a 映射 row shows its keys in (#84).
struct HotkeyRecorderView: NSViewRepresentable {
    var hotkey: Hotkey?
    var accessibilityName: String
    var isRecordable = true
    var width = HotkeyRecorderField.defaultWidth
    var onCapture: (Hotkey) -> Void = { _ in }
    var onClear: (() -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderField {
        HotkeyRecorderField(recordsModifierTaps: false, width: width)
    }

    func updateNSView(_ field: HotkeyRecorderField, context: Context) {
        field.accessibilityName = accessibilityName
        field.face = HotkeyRecorderModel.face(of: hotkey)
        field.isBound = hotkey != nil
        field.isRecordable = isRecordable
        field.onCapture = { if case .keystroke(let captured) = $0 { onCapture(captured) } }
        field.onClear = onClear
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HotkeyRecorderField, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// Records a 视频控制 key (#79): either a modifier tapped on its own — judged by the same
/// `ModifierTapRecognizer` that listens in Ghost Mode, so what records is exactly what fires — or
/// an ordinary key or combo, taken on key-down.
struct VideoControlRecorderView: NSViewRepresentable {
    var trigger: VideoControlTrigger?
    var accessibilityName: String
    var onCapture: (VideoControlTrigger) -> Void
    var onClear: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderField {
        HotkeyRecorderField(recordsModifierTaps: true, width: HotkeyRecorderField.defaultWidth)
    }

    func updateNSView(_ field: HotkeyRecorderField, context: Context) {
        field.accessibilityName = accessibilityName
        field.face = HotkeyRecorderModel.face(of: trigger)
        field.isBound = trigger != nil
        field.onCapture = onCapture
        field.onClear = onClear
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HotkeyRecorderField, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// The settings panel's one recorder control (#82): a fixed-width field that always draws the
/// four modifier slots — dim when unused, accent when part of the combo — so an unbound field
/// reads as empty at a glance and every row's combo lines up. Click to record; while recording,
/// a bare Esc cancels and a bare ⌫/⌦ clears (`HotkeyRecorderModel`), as does leaving the field.
///
/// Colors are read in `draw(_:)`, not cached, so the field follows light/dark and accent changes.
final class HotkeyRecorderField: NSView, KeyCapturingResponder {
    static let defaultWidth: CGFloat = 200
    /// A 映射 row holds two fields side by side, so each is narrower.
    static let mappingWidth: CGFloat = 170
    static let height: CGFloat = 24

    var face: RecorderFace = .slots(lit: [], key: nil) { didSet { if face != oldValue { needsDisplay = true } } }
    var isBound = false { didSet { refreshClearButton() } }
    var accessibilityName = "" { didSet { refreshAccessibility() } }
    var onCapture: ((VideoControlTrigger) -> Void)?
    var onClear: (() -> Void)? { didSet { refreshClearButton() } }
    /// `false` for the read-only form: no recording, no ⓧ.
    var isRecordable = true { didSet { refreshClearButton() } }

    private(set) var isCapturingKeys = false
    private let recordsModifierTaps: Bool
    private let width: CGFloat
    private var tapRecognizer = ModifierTapRecognizer()
    private let clearButton = NSButton()

    private var prompt: String { recordsModifierTaps ? "按下按键，或单独轻按修饰键…" : "按下组合键…" }

    init(recordsModifierTaps: Bool, width: CGFloat) {
        self.recordsModifierTaps = recordsModifierTaps
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refreshClearButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: Self.height) }
    override var acceptsFirstResponder: Bool { isRecordable }

    // MARK: Recording

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return true
    }

    private func startRecording() {
        guard isRecordable, !isCapturingKeys else { return }
        isCapturingKeys = true
        tapRecognizer = ModifierTapRecognizer()
        window?.makeFirstResponder(self)
        refreshClearButton()
        needsDisplay = true
    }

    private func stopRecording() {
        guard isCapturingKeys else { return }
        isCapturingKeys = false
        refreshClearButton()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturingKeys, let raw = RawInputEvent(event),
              case .keyDown(let keyCode, let modifierFlags, _, _) = raw
        else {
            super.keyDown(with: event)
            return
        }
        _ = tapRecognizer.handle(raw)
        switch HotkeyRecorderModel.outcome(ofKeyDown: keyCode, modifierFlags: modifierFlags) {
        case .cancel:
            stopRecording()
        case .clear:
            stopRecording()
            onClear?()
        case .capture(let hotkey):
            stopRecording()
            onCapture?(.keystroke(hotkey))
        }
    }

    /// ⌘-combos reach the window's key-equivalent pass (and the menu bar) before `keyDown` —
    /// while recording they are the combo being recorded, not a menu command.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturingKeys, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturingKeys, recordsModifierTaps, let raw = RawInputEvent(event) else {
            super.flagsChanged(with: event)
            return
        }
        if let tapped = tapRecognizer.handle(raw) {
            stopRecording()
            onCapture?(.modifierTap(tapped))
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    @objc private func clearClicked() {
        stopRecording()
        onClear?()
    }

    private func refreshClearButton() {
        clearButton.isHidden = !isBound || onClear == nil || !isRecordable || isCapturingKeys
        setAccessibilityRole(isRecordable ? .button : .staticText)
        clearButton.setAccessibilityLabel("清除\(accessibilityName)按键")
    }

    private func refreshAccessibility() {
        setAccessibilityLabel(accessibilityName)
        refreshClearButton()
    }

    override func accessibilityValue() -> Any? {
        switch face {
        case .slots(_, nil): "未设置"
        case .slots(let lit, let key?): ModifierSlot.allCases.filter(lit.contains).map(\.glyph).joined() + key
        case .singleCap(let cap): cap
        }
    }

    // MARK: Drawing

    private static let horizontalInset: CGFloat = 9
    private static let glyphFont = NSFont.systemFont(ofSize: 14, weight: .medium)

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        NSColor.quaternarySystemFill.setFill()
        shape.fill()
        (isCapturingKeys ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = isCapturingKeys ? 2 : 1
        shape.stroke()

        if isCapturingKeys {
            draw(prompt, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, at: Self.horizontalInset)
            return
        }
        switch face {
        case .slots(let lit, let key):
            var x = Self.horizontalInset
            for slot in ModifierSlot.allCases {
                let color: NSColor = lit.contains(slot) ? .controlAccentColor : .tertiaryLabelColor
                x += draw(slot.glyph, font: Self.glyphFont, color: color, at: x) + 3
            }
            if let key {
                draw(key, font: Self.glyphFont, color: .controlAccentColor, at: x + 6)
            }
        case .singleCap(let cap):
            draw(cap, font: Self.glyphFont, color: .controlAccentColor, at: Self.horizontalInset)
        }
    }

    /// Draws `text` vertically centered with its leading edge at `x`; returns its width.
    @discardableResult
    private func draw(_ text: String, font: NSFont, color: NSColor, at x: CGFloat) -> CGFloat {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        string.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
        return size.width
    }
}
