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
/// Always starts in `.normal` and is never told to restore a prior Ghost Mode — the caller
/// (`Orchestrator`) constructs a fresh instance on every launch, which is what gives "restart
/// always returns to Normal Mode" (ADR-0006) for free, with no persisted-state path to bypass.
public final class GhostModeController {
    private let platformOps: PlatformOps
    private let window: WidgetWindowHandle
    private let ghostOpacity: Double
    public private(set) var mode: WidgetMode = .normal

    public init(platformOps: PlatformOps, window: WidgetWindowHandle, ghostOpacity: Double) {
        self.platformOps = platformOps
        self.window = window
        self.ghostOpacity = ghostOpacity
        platformOps.onMouseEntered(window) { [weak self] in
            self?.handleMouseEntered()
        }
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

    private func enterGhostMode() {
        mode = .ghost
        platformOps.setNativeChromeVisible(false, in: window)
        platformOps.setToolbarVisible(false, in: window)
        platformOps.setContentOpacity(ghostOpacity, in: window)
        platformOps.setMousePassthrough(true, in: window)
        platformOps.setPinned(true, in: window)
    }

    private func leaveGhostMode() {
        mode = .normal
        platformOps.setNativeChromeVisible(true, in: window)
        platformOps.setToolbarVisible(true, in: window)
        platformOps.setContentOpacity(1.0, in: window)
        platformOps.setMousePassthrough(false, in: window)
        platformOps.setPinned(false, in: window)
        platformOps.setWindowHidden(false, in: window)
    }

    private func handleMouseEntered() {
        // Moving back out deliberately does not restore the window — the only way out is
        // toggling Ghost Mode off again, or the tray icon (#9).
        guard mode == .ghost else { return }
        platformOps.setWindowHidden(true, in: window)
    }
}
