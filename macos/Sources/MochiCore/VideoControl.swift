import Foundation

/// The actions 视频控制 (#74) binds keys to. Each case's `rawValue` is the stable identifier the
/// config file stores a binding under — never the declaration order, like `HotkeyAction`.
public enum VideoControlAction: String, CaseIterable, Hashable, Sendable {
    case togglePlayback = "toggle_playback"

    /// What the action is bound to until the user says otherwise; `nil` means unbound.
    public var defaultTrigger: VideoControlTrigger? {
        switch self {
        case .togglePlayback: .modifierTap(.rightOption)
        }
    }
}

/// A key 视频控制 listens for (#74): a side-specific modifier tapped on its own — the default,
/// because tapping a modifier types nothing and moves no cursor in any app — or an ordinary key
/// or combo.
public enum VideoControlTrigger: Hashable {
    case modifierTap(ModifierKey)
    case keystroke(Hotkey)
}

/// What 视频控制 asks the page to do to its target video.
public enum VideoCommand: Equatable, Sendable {
    case togglePlayback
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
    /// widget, only with at least one key bound. Idempotent, so every caller can just call it.
    public func refreshObservation() {
        let shouldObserve = isGhostModeActive() && currentWindow() != nil
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
        guard let tapped = tapRecognizer.handle(event) else { return }
        let config = currentConfig()
        guard let action = VideoControlAction.allCases.first(where: {
            config.videoControlTrigger(for: $0) == .modifierTap(tapped)
        }) else { return }
        platformOps.performVideoCommand(command(for: action), in: window)
    }

    private func command(for action: VideoControlAction) -> VideoCommand {
        switch action {
        case .togglePlayback: .togglePlayback
        }
    }
}
