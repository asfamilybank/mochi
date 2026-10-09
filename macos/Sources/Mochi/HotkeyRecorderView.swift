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
///
/// `target` is a combo trigger unless this is a mapping's page key, which may be any keystroke;
/// a key that doesn't fit is turned away through `onHint` and recording goes on (#89, #90).
struct HotkeyRecorderView: NSViewRepresentable {
    var hotkey: Hotkey?
    var accessibilityName: String
    var isRecordable = true
    var width = HotkeyRecorderField.defaultWidth
    var target = RecorderTarget.trigger(.combo)
    var onRecordingStarted: () -> Void = {}
    var onHint: (HotkeyRejection) -> Void = { _ in }
    var onCapture: (Hotkey) -> Void = { _ in }
    var onClear: (() -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderField {
        HotkeyRecorderField(width: width)
    }

    func updateNSView(_ field: HotkeyRecorderField, context: Context) {
        field.accessibilityName = accessibilityName
        field.face = HotkeyRecorderModel.face(of: hotkey)
        field.isBound = hotkey != nil
        field.isRecordable = isRecordable
        field.target = target
        field.onRecordingStarted = onRecordingStarted
        field.onHint = onHint
        field.onCapture = { if case .keystroke(let captured) = $0 { onCapture(captured) } }
        field.onClear = onClear
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HotkeyRecorderField, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// Records a 视频控制 key (#79) of the `kind` its row's dropdown picked (#90): a modifier tapped
/// on its own — judged by the same `ModifierTapRecognizer` that listens in Ghost Mode, so what
/// records is exactly what fires — or a combo, taken on key-down.
///
/// Bumping `recordingRequest` starts recording, the way picking a kind in the dropdown does;
/// `onRecordingStopped` fires however recording ends, captured or not, so the row can drop the
/// kind it was only trying out.
struct TriggerKeyRecorderView: NSViewRepresentable {
    var trigger: TriggerKey?
    var kind: TriggerKind
    var accessibilityName: String
    var recordingRequest = 0
    var onRecordingStarted: () -> Void = {}
    var onRecordingStopped: () -> Void = {}
    var onHint: (HotkeyRejection) -> Void = { _ in }
    var onCapture: (TriggerKey) -> Void
    var onClear: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderField {
        HotkeyRecorderField(width: HotkeyRecorderField.defaultWidth)
    }

    func updateNSView(_ field: HotkeyRecorderField, context: Context) {
        field.accessibilityName = accessibilityName
        field.face = HotkeyRecorderModel.face(of: trigger)
        field.isBound = trigger != nil
        field.target = .trigger(kind)
        field.onRecordingStarted = onRecordingStarted
        field.onRecordingStopped = onRecordingStopped
        field.onHint = onHint
        field.onCapture = onCapture
        field.onClear = onClear
        field.recordingRequest = recordingRequest
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
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onHint: ((HotkeyRejection) -> Void)?
    var onCapture: ((TriggerKey) -> Void)?
    var onClear: (() -> Void)? { didSet { refreshClearButton() } }
    /// `false` for the read-only form: no recording, no ⓧ.
    var isRecordable = true { didSet { refreshClearButton() } }

    /// What a key pressed while recording is judged against (#90).
    var target = RecorderTarget.trigger(.combo) {
        didSet {
            guard target != oldValue else { return }
            tapRecognizer = HotkeyRecorderModel.tapRecognizer(recording: target)
            needsDisplay = true
        }
    }
    /// A new value starts recording — on the next turn of the run loop, since it arrives in the
    /// middle of a SwiftUI update and starting tells the row to clear its hint.
    var recordingRequest = 0 {
        didSet {
            guard recordingRequest != oldValue else { return }
            DispatchQueue.main.async { [weak self] in self?.startRecording() }
        }
    }

    private(set) var isCapturingKeys = false
    private let width: CGFloat
    private var tapRecognizer = HotkeyRecorderModel.tapRecognizer(recording: .trigger(.combo))
    private let clearButton = NSButton()
    /// While recording: a click anywhere else in the app ends it, even on something that doesn't
    /// take first responder (a blank stretch of the pane).
    private var clickElsewhereMonitor: Any?

    private var prompt: String {
        switch target {
        case .trigger(.tap): "轻按一颗修饰键…"
        case .trigger(.doubleTap): "连按两次修饰键…"
        case .trigger(.combo): "按下组合键…"
        case .pageKeystroke: "按下按键…"
        }
    }

    init(width: CGFloat) {
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
        tapRecognizer = HotkeyRecorderModel.tapRecognizer(recording: target)
        onRecordingStarted?()
        window?.makeFirstResponder(self)
        clickElsewhereMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.stopRecording()
            }
            return event
        }
        refreshClearButton()
        needsDisplay = true
    }

    private func stopRecording() {
        guard isCapturingKeys else { return }
        isCapturingKeys = false
        if let clickElsewhereMonitor { NSEvent.removeMonitor(clickElsewhereMonitor) }
        clickElsewhereMonitor = nil
        refreshClearButton()
        needsDisplay = true
        onRecordingStopped?()
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturingKeys, let raw = RawInputEvent(event),
              case .keyDown(let keyCode, let modifierFlags, _, _) = raw
        else {
            super.keyDown(with: event)
            return
        }
        _ = tapRecognizer.handle(raw)
        switch HotkeyRecorderModel.outcome(ofKeyDown: keyCode, modifierFlags: modifierFlags, recording: target) {
        case .cancel:
            stopRecording()
        case .clear:
            stopRecording()
            onClear?()
        case .capture(let hotkey):
            stopRecording()
            onCapture?(.keystroke(hotkey))
        case .captureTap(let tap):
            stopRecording()
            onCapture?(tap.trigger)
        case .hint(let rejection):
            onHint?(rejection)
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
        guard isCapturingKeys, let raw = RawInputEvent(event) else {
            super.flagsChanged(with: event)
            return
        }
        for tap in tapRecognizer.handle(raw) {
            if case .captureTap(let captured)? = HotkeyRecorderModel.outcome(of: tap, recording: target) {
                stopRecording()
                onCapture?(captured.trigger)
                return
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    /// Switching to another app or window doesn't resign first responder — the field would still
    /// be recording when the user came back — so leaving the window ends it too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowDidResignKey() {
        stopRecording()
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
