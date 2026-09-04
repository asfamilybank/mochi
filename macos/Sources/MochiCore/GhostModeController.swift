import Foundation

public enum WidgetMode: Equatable {
    case normal
    case ghost
}

/// The Ghost Mode state machine (#8): a single hotkey flips between `.normal` and `.ghost`,
/// where Ghost Mode bundles native-chrome visibility, toolbar visibility, content opacity,
/// mouse passthrough, and always-on-top into one atomic transition (ADR-0006/ADR-0012) — there
/// is no way to reach a state with, say, passthrough on but the toolbar still showing.
///
/// Always-on-top is internal to this transition, not a standalone feature: floating above other
/// windows only means anything while invisibly overlaying them, which is what Ghost Mode is
/// (ADR-0012). Normal Mode is a plain window at the normal level, so this controller is the only
/// caller of `setPinned` in the whole app.
///
/// It is also the single decider of how visible the window is. "Hidden" and "translucent" would
/// otherwise both write `NSWindow.alphaValue` and fight over it, so this type folds every input
/// into one `effectiveOpacity` and the platform layer just applies it (ADR-0012).
///
/// Always starts in `.normal` and is never told to restore a prior Ghost Mode — the caller
/// (`Orchestrator`) constructs a fresh instance on every launch, which is what gives "restart
/// always returns to Normal Mode" (ADR-0006) for free, with no persisted-state path to bypass.
public final class GhostModeController {
    private let platformOps: PlatformOps
    private let window: WidgetWindowHandle
    private let ghostOpacity: Double
    public private(set) var mode: WidgetMode = .normal
    /// The boss key's (ADR-0012) own bookkeeping: deliberate, persists until deliberately undone
    /// (or until Ghost Mode is left), and never decays on its own.
    private var isHidden = false

    public init(platformOps: PlatformOps, window: WidgetWindowHandle, ghostOpacity: Double) {
        self.platformOps = platformOps
        self.window = window
        self.ghostOpacity = ghostOpacity
    }

    public func toggle() {
        switch mode {
        case .normal: enterGhostMode()
        case .ghost: leaveGhostMode()
        }
    }

    /// Forces the widget back to Normal Mode regardless of current state — the tray icon's
    /// "Exit Ghost Mode" entry (#9) must work even while the window is fully hidden/click-through,
    /// and must be a no-op when already in Normal Mode rather than toggling back into Ghost Mode.
    public func exitGhostMode() {
        guard mode == .ghost else { return }
        leaveGhostMode()
    }

    /// The boss key (ADR-0012): makes the window completely invisible while leaving it in place
    /// so the page keeps running — the video the user is listening to must not stall. A silent
    /// no-op in Normal Mode, which is a plain macOS window with no visibility concept of its own
    /// beyond what the system already provides (`⌘M`).
    public func toggleHidden() {
        guard mode == .ghost else { return }
        isHidden.toggle()
        applyEffectiveOpacity()
    }

    /// `Hidden → 0`; `Ghost → 目标透明度`; `Normal → 1.0`. The single source of the window's
    /// visibility, so no two features can disagree about it.
    private var effectiveOpacity: Double {
        guard mode == .ghost else { return 1.0 }
        return isHidden ? 0 : ghostOpacity
    }

    private func applyEffectiveOpacity() {
        platformOps.setContentOpacity(effectiveOpacity, in: window)
    }

    private func enterGhostMode() {
        mode = .ghost
        platformOps.setNativeChromeVisible(false, in: window)
        platformOps.setToolbarVisible(false, in: window)
        applyEffectiveOpacity()
        platformOps.setMousePassthrough(true, in: window)
        platformOps.setPinned(true, in: window)
    }

    private func leaveGhostMode() {
        mode = .normal
        isHidden = false
        platformOps.setNativeChromeVisible(true, in: window)
        platformOps.setToolbarVisible(true, in: window)
        applyEffectiveOpacity()
        platformOps.setMousePassthrough(false, in: window)
        platformOps.setPinned(false, in: window)
        // The only moment the widget is allowed to take focus (ADR-0012) — the user just asked
        // to interact with it. Entering or staying in Ghost Mode never fronts the window, so it
        // can't steal focus from whatever app the user is actually working in.
        platformOps.showWindow(window)
    }
}
