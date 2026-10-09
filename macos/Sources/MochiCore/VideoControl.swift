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
    public var defaultTrigger: VideoControlTrigger? {
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

/// A key 视频控制 listens for (#74): a side-specific modifier tapped on its own — the default,
/// because tapping a modifier types nothing and moves no cursor in any app — or an ordinary key
/// or combo.
public enum VideoControlTrigger: Hashable {
    case modifierTap(ModifierKey)
    case keystroke(Hotkey)

    /// Which of the three kinds of trigger key this is (#90) — what the settings row's
    /// dropdown shows.
    public var kind: TriggerKind {
        switch self {
        case .modifierTap: .tap
        case .keystroke: .combo
        }
    }
}

/// How a trigger key is pressed (CONTEXT.md, ADR-0022): a modifier tapped on its own, or a
/// combo. The settings rows that can take either let the user pick one first (#90).
public enum TriggerKind: CaseIterable, Hashable, Sendable {
    case tap
    case combo

    public var displayName: String {
        switch self {
        case .tap: "轻按"
        case .combo: "组合键"
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
/// the configured keys and turns each one into a `VideoCommand` on the widget's page.
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
    private var isObserving = false
    private var hasRequestedAccessibility = false
    private var tapRecognizer = ModifierTapRecognizer()

    public init(
        platformOps: PlatformOps,
        currentConfig: @escaping () -> WidgetConfig,
        isGhostModeActive: @escaping () -> Bool,
        currentWindow: @escaping () -> WidgetWindowHandle?
    ) {
        self.platformOps = platformOps
        self.currentConfig = currentConfig
        self.isGhostModeActive = isGhostModeActive
        self.currentWindow = currentWindow
    }

    /// Starts or stops listening to match the current state: only in Ghost Mode, only with a
    /// widget, only with at least one key bound — with nothing bound there is nothing to listen
    /// for, and no reason to ask for Accessibility either. Idempotent, so every caller can just
    /// call it: a mode change, a widget close, and every settings edit
    /// (`Orchestrator.reapplyConfiguration()`).
    public func refreshObservation() {
        let config = currentConfig()
        let anythingBound = VideoControlAction.allCases.contains { config.videoControlTrigger(for: $0) != nil }
        let shouldObserve = isGhostModeActive() && currentWindow() != nil && anythingBound
        if shouldObserve, !isObserving {
            if !platformOps.isAccessibilityTrusted(), !hasRequestedAccessibility {
                hasRequestedAccessibility = true
                platformOps.requestAccessibilityPermission()
            }
            isObserving = true
            tapRecognizer = ModifierTapRecognizer()
            platformOps.startObservingInput { [weak self] event in
                self?.handle(event)
            }
        } else if !shouldObserve, isObserving {
            isObserving = false
            platformOps.stopObservingInput()
        }
    }

    private func handle(_ event: RawInputEvent) {
        guard isGhostModeActive(), let window = currentWindow() else { return }
        // Every event goes through the recognizer, even one that is itself a match: a key going
        // down is also what cancels a modifier tap in progress.
        let tapped = tapRecognizer.handle(event)
        let trigger: VideoControlTrigger
        if let tapped {
            trigger = .modifierTap(tapped)
        } else if case .keyDown(let keyCode, let modifierFlags, isRepeat: false, _) = event {
            trigger = .keystroke(Hotkey(keyCode: keyCode, modifierFlags: modifierFlags))
        } else {
            return
        }
        let config = currentConfig()
        guard let action = VideoControlAction.allCases.first(where: { config.videoControlTrigger(for: $0) == trigger })
        else { return }
        platformOps.performVideoCommand(command(for: action, step: Double(config.videoSeekStep)), in: window)
    }

    private func command(for action: VideoControlAction, step: Double) -> VideoCommand {
        switch action {
        case .togglePlayback: .togglePlayback
        case .seekBackward: .seek(seconds: -step)
        case .seekForward: .seek(seconds: step)
        }
    }
}
