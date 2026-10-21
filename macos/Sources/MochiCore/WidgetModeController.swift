import Foundation

public enum WidgetMode: Equatable, Sendable {
    case normal
    /// The page alone, translucent and above other windows, yet an ordinary focusable window
    /// (#147, ADR-0035).
    case float
    case ghost
}

/// The widget's mode state machine (#8, generalized by #146): which mode the widget is in, plus
/// Hidden as a separate dimension that only means anything in some modes (`canHide`).
///
/// Each mode outside Normal is a bundled state (ADR-0006, ADR-0035): entering it applies its
/// chrome, content opacity, mouse passthrough and always-on-top together, so there is no way to
/// reach, say, passthrough on with the toolbar still showing. Ghost Mode is the click-through,
/// never-focused one (ADR-0012); Float Mode keeps the page usable and takes focus. Each has its own
/// key: it enters that mode, or returns to Normal Mode from it, and Float and Ghost switch
/// straight into each other.
///
/// Always-on-top belongs to these bundles, not to a standalone feature, so this controller is the
/// only caller of `setPinned` in the whole app.
///
/// It is also the single decider of how visible the window is. "Hidden" and "translucent" would
/// otherwise both write `NSWindow.alphaValue` and fight over it, so this type folds every input
/// into one `effectiveOpacity` and the platform layer just applies it (ADR-0012).
///
/// Always starts in `.normal` and is never told to restore a prior mode — the caller
/// (`Orchestrator`) constructs a fresh instance every time the widget window is opened, which is
/// what gives both "restart always returns to Normal Mode" (ADR-0006) and "reopening the closed
/// widget returns to Normal Mode" (#42) for free, with no persisted-state path to bypass.
///
/// Reads the target opacities from `currentConfig` *at the moment they are needed* rather than
/// capturing them at construction (#46) — that is what makes a settings-panel edit take effect
/// without a restart, and it needs no notification for the common case (the next entry simply
/// sees the new value).
/// `reapplyConfiguration()` covers the one case where nothing else would trigger a re-read: an
/// edit made while already sitting in a translucent mode.
public final class WidgetModeController {
    private let platformOps: PlatformOps
    private let window: WidgetWindowHandle
    private let currentConfig: () -> WidgetConfig
    public private(set) var mode: WidgetMode = .normal
    /// The boss key's (ADR-0012) own bookkeeping: deliberate, persists until deliberately undone
    /// (or until Normal Mode is returned to), and never decays on its own. Switching between Float
    /// and Ghost keeps it (#148, ADR-0035): the window stays out of sight, only the mode underneath
    /// changes. Readable so the tray's 隐藏窗口 (#63) can show a checkmark; only `toggleHidden()`
    /// and leaving for Normal Mode write it.
    public private(set) var isHidden = false
    /// Told after every change of mode or of Hidden, once the transition is complete — how 视频控制
    /// (#74) knows to start or stop listening, and how 不打扰 knows it just began (#148).
    public var onStateChanged: (() -> Void)?

    public init(platformOps: PlatformOps, window: WidgetWindowHandle, currentConfig: @escaping () -> WidgetConfig) {
        self.platformOps = platformOps
        self.window = window
        self.currentConfig = currentConfig
    }

    /// Pushes the current config's opacity down right now — for an edit made *while in a
    /// translucent mode*, where otherwise nothing would happen until the next mode change and the
    /// user dragging the opacity slider would see no change (#46). A silent no-op in Normal Mode:
    /// the window is opaque there regardless of any setting, and the platform must not be told to
    /// change an opacity it never had.
    public func reapplyConfiguration() {
        guard mode != .normal else { return }
        applyEffectiveOpacity()
    }

    public func toggleGhostMode() {
        switch mode {
        case .normal, .float: enterGhostMode()
        case .ghost: leaveForNormalMode()
        }
    }

    public func toggleFloatMode() {
        switch mode {
        case .normal, .ghost: enterFloatMode()
        case .float: leaveForNormalMode()
        }
    }

    /// Forces the widget back to Normal Mode from whatever mode it is in — `Orchestrator.openWidget()`
    /// (the tray's 打开窗口, the Dock) must work even while the window is fully hidden/click-through,
    /// and must be a no-op when already in Normal Mode rather than toggling into another mode.
    /// (The tray's own 退出幽灵模式 entry from #9 was folded into its 幽灵模式 toggle by #63.)
    public func returnToNormalMode() {
        guard mode != .normal else { return }
        leaveForNormalMode()
    }

    /// Whether Hidden means anything in the current mode — Float and Ghost share it (#148,
    /// ADR-0035). Normal Mode is a plain window, so never there. The tray's 隐藏窗口 greys out on
    /// exactly this.
    public var canHide: Bool {
        switch mode {
        case .normal: false
        case .float, .ghost: true
        }
    }

    /// The boss key (ADR-0012): makes the window completely invisible while leaving it in place
    /// so the page keeps running. Going Hidden pauses every playing video and audio on the page —
    /// hiding means "I can't watch this right now" — and coming back resumes nothing, so the user
    /// picks up exactly where they left off, when they choose to (ADR-0021). A silent no-op where
    /// `canHide` says so: in Normal Mode, a plain macOS window with no visibility concept of its
    /// own beyond what the system already provides (`⌘M`).
    ///
    /// Coming back only makes the window visible again, in Float Mode too: it never activates, so
    /// focus stays with whatever app the user is in until they click the page (ADR-0035).
    public func toggleHidden() {
        guard canHide else { return }
        isHidden.toggle()
        applyEffectiveOpacity()
        applyMousePassthrough()
        if isHidden {
            platformOps.pauseAllMedia(in: window)
            giveUpFocusUnlessAnotherWindowHasIt()
        }
        onStateChanged?()
    }

    /// Hidden → fully invisible; Float and Ghost → their configured targets; Normal → opaque. The
    /// single source of the window's visibility, so no two features can disagree about it.
    private var effectiveOpacity: Double {
        if isHidden { return 0 }
        switch mode {
        case .normal: return 1.0
        case .float: return currentConfig().floatOpacity
        case .ghost: return currentConfig().ghostOpacity
        }
    }

    private func applyEffectiveOpacity() {
        platformOps.setContentOpacity(effectiveOpacity, in: window)
    }

    /// Ghost Mode is click-through by definition; a hidden Float Mode window is too, so a window
    /// nobody can see never catches a click meant for the app underneath (#148).
    private func applyMousePassthrough() {
        platformOps.setMousePassthrough(mode == .ghost || isHidden, in: window)
    }

    private func enterGhostMode() {
        // Asked before the chrome comes off: losing its title bar takes the widget out of key.
        let anotherWindowIsKey = platformOps.isAnotherWindowKey(than: window)
        mode = .ghost
        platformOps.setWindowChrome(.ghost, in: window)
        applyEffectiveOpacity()
        applyMousePassthrough()
        platformOps.setPinned(true, in: window)
        if !anotherWindowIsKey { platformOps.deactivateApp() }
        onStateChanged?()
    }

    /// Float Mode is for using the page (ADR-0035), so entering it brings the widget forward and
    /// makes it key — from Ghost Mode too, which is the user asking to interact again. Unless the
    /// window is hidden (#148): it stays hidden in Float Mode, and an invisible window taking focus
    /// would swallow the user's typing.
    private func enterFloatMode() {
        mode = .float
        platformOps.setWindowChrome(.float, in: window)
        applyEffectiveOpacity()
        applyMousePassthrough()
        platformOps.setPinned(true, in: window)
        if !isHidden { platformOps.showWindow(window) }
        onStateChanged?()
    }

    /// Going Ghost or Hidden means getting out of the way, menu bar included: whatever app was
    /// active before Mochi gets focus back — unless focus is on another Mochi window, such as the
    /// settings window someone is tuning the opacity in, which is an ordinary window.
    private func giveUpFocusUnlessAnotherWindowHasIt() {
        if !platformOps.isAnotherWindowKey(than: window) { platformOps.deactivateApp() }
    }

    private func leaveForNormalMode() {
        mode = .normal
        isHidden = false
        platformOps.setWindowChrome(.normal, in: window)
        applyEffectiveOpacity()
        applyMousePassthrough()
        platformOps.setPinned(false, in: window)
        // The user just asked to interact with the widget: the one moment leaving Ghost Mode may
        // take focus (ADR-0012). Entering or staying in Ghost Mode never fronts the window, so it
        // can't steal focus from whatever app the user is actually working in.
        platformOps.showWindow(window)
        onStateChanged?()
    }
}
