import Foundation

/// The actions 视频控制 (#74) binds keys to. Each case's `rawValue` is the stable identifier the
/// config file stores a binding under — never the declaration order, like `HotkeyAction`.
public enum VideoControlAction: String, CaseIterable, Hashable, Sendable {
    case togglePlayback = "toggle_playback"
    case seekBackward = "seek_backward"
    case seekForward = "seek_forward"

    /// What the action is bound to until the user says otherwise; `nil` means unbound. Forward
    /// starts unbound: the modifiers left after right ⌥ and right ⌘ all have side effects
    /// (right ⇧ switches many Chinese input methods), so Mochi won't claim one on its own.
    public var defaultTrigger: TriggerKey? {
        switch self {
        case .togglePlayback: .modifierTap(.rightOption)
        case .seekBackward: .modifierTap(.rightCommand)
        case .seekForward: nil
        }
    }

    /// The settings panel's label for the action (#79).
    public var displayName: String {
        switch self {
        case .togglePlayback: "播放/暂停"
        case .seekBackward: "后退"
        case .seekForward: "前进"
        }
    }
}

/// What 视频控制 asks the page to do to its target video.
public enum VideoCommand: Equatable, Sendable {
    case togglePlayback
    /// Moves playback by `seconds` (negative is back), clamped to the video, leaving it playing
    /// or paused as it was. A live stream, with no finite duration, is left alone.
    case seek(seconds: Double)
}

/// Drives 视频控制 (#74, ADR-0020): while Ghost Mode is active, listens — never intercepts — for
/// the configured keys and turns each one into a `VideoCommand` on the widget's page. Since #92
/// it is also the ear of every Hotkey Forwarding mapping set off by a tap or a double tap — those
/// are never registered with Carbon — handing their page keystroke to `HotkeyForwarder`; one
/// recognizer serves both, so a key bound both ways across the two waits the same way.
///
/// App-global like `HotkeyForwarder`, built once by `Orchestrator.start()`, so the "ask for
/// Accessibility at most once per launch" bookkeeping survives a widget close and reopen. Whether
/// to listen is recomputed by `refreshObservation()` whenever its inputs change — the mode, the
/// window's existence, the bindings — and every key is resolved against the config read at the
/// moment it is pressed.
public final class VideoControl {
    private let platformOps: PlatformOps
    private let currentConfig: () -> WidgetConfig
    private let isGhostModeActive: () -> Bool
    private let currentWindow: () -> WidgetWindowHandle?
    /// Hands a tap-triggered mapping's page keystroke to Hotkey Forwarding (#92).
    private let forward: (Hotkey) -> Void
    private var isObserving = false
    private var hasRequestedAccessibility = false
    private var tapRecognizer = TriggerTapRecognizer()
    /// Cancels the wait on `tapRecognizer`'s held-back tap, while there is one.
    private var cancelHeldBackTapRelease: (() -> Void)?

    public init(
        platformOps: PlatformOps,
        currentConfig: @escaping () -> WidgetConfig,
        isGhostModeActive: @escaping () -> Bool,
        currentWindow: @escaping () -> WidgetWindowHandle?,
        forward: @escaping (Hotkey) -> Void = { _ in }
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.isGhostModeActive = isGhostModeActive
        self.currentWindow = currentWindow
        self.forward = forward
    }

    /// Starts or stops listening to match the current state: only in Ghost Mode, only with a
    /// widget, only with at least one key bound — with nothing bound there is nothing to listen
    /// for, and no reason to ask for Accessibility either. Idempotent, so every caller can just
    /// call it: a mode change, a widget close, and every settings edit
    /// (`Orchestrator.reapplyConfiguration()`).
    public func refreshObservation() {
        let config = currentConfig()
        let anythingBound = !Self.listenedTriggers(in: config).isEmpty
        let shouldObserve = isGhostModeActive() && currentWindow() != nil && anythingBound
        if shouldObserve, !isObserving {
            if !platformOps.isAccessibilityTrusted(), !hasRequestedAccessibility {
                hasRequestedAccessibility = true
                platformOps.requestAccessibilityPermission()
            }
            isObserving = true
            tapRecognizer = TriggerTapRecognizer()
            platformOps.startObservingInput { [weak self] event in
                self?.handle(event)
            }
        } else if !shouldObserve, isObserving {
            isObserving = false
            platformOps.stopObservingInput()
            cancelHeldBackTapRelease?()
            cancelHeldBackTapRelease = nil
        }
    }

    private func handle(_ event: RawInputEvent) {
        guard isGhostModeActive(), currentWindow() != nil else { return }
        let config = currentConfig()
        // Which keys are bound which way decides whether a tap must wait to see if a second
        // follows (#91) — read from the config at the moment of the press, like everything else.
        let bound = Self.listenedTriggers(in: config)
        tapRecognizer.tapKeys = Set(bound.compactMap { if case .modifierTap(let key) = $0 { key } else { nil } })
        tapRecognizer.doubleTapKeys = Set(bound.compactMap { if case .modifierDoubleTap(let key) = $0 { key } else { nil } })
        let heldBackBefore = tapRecognizer.heldBackTap
        // Every event goes through the recognizer, even one that is itself a match: a key going
        // down is also what cancels a modifier tap in progress.
        for tapEvent in tapRecognizer.handle(event) {
            perform(tapEvent.trigger)
        }
        if case .keyDown(let keyCode, let modifierFlags, isRepeat: false, _) = event {
            perform(.keystroke(Hotkey(keyCode: keyCode, modifierFlags: modifierFlags)))
        }
        if tapRecognizer.heldBackTap != heldBackBefore {
            waitOutHeldBackTap()
        }
    }

    /// Restarts the wait for whatever tap `tapRecognizer` now holds back: when the double-tap
    /// interval passes with no second tap, it was a tap after all.
    private func waitOutHeldBackTap() {
        cancelHeldBackTapRelease?()
        cancelHeldBackTapRelease = nil
        guard tapRecognizer.heldBackTap != nil else { return }
        cancelHeldBackTapRelease = platformOps.schedule(after: TriggerTapRecognizer.doubleTapInterval) { [weak self] in
            guard let self else { return }
            cancelHeldBackTapRelease = nil
            guard isGhostModeActive(), let tap = tapRecognizer.releaseHeldBackTap() else { return }
            perform(tap.trigger)
        }
    }

    private func perform(_ trigger: TriggerKey) {
        guard let window = currentWindow() else { return }
        let config = currentConfig()
        if let action = VideoControlAction.allCases.first(where: { config.videoControlTrigger(for: $0) == trigger }) {
            platformOps.performVideoCommand(command(for: action, step: Double(config.videoSeekStep)), in: window)
        } else if trigger.kind != .combo, let mapping = config.hotkeyMappings.first(where: { $0.trigger == trigger }) {
            // A combo mapping is Carbon's to dispatch; hearing its keyDown here too would forward twice.
            forward(mapping.pageKeystroke)
        }
    }

    /// Every trigger key this listener answers for: the bound video keys, and since #92 the
    /// mappings set off by a tap or a double tap.
    private static func listenedTriggers(in config: WidgetConfig) -> [TriggerKey] {
        VideoControlAction.allCases.compactMap { config.videoControlTrigger(for: $0) }
            + config.hotkeyMappings.map(\.trigger).filter { $0.kind != .combo }
    }

    private func command(for action: VideoControlAction, step: Double) -> VideoCommand {
        switch action {
        case .togglePlayback: .togglePlayback
        case .seekBackward: .seek(seconds: -step)
        case .seekForward: .seek(seconds: step)
        }
    }
}
