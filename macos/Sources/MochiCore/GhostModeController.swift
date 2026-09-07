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
/// (`Orchestrator`) constructs a fresh instance every time the widget window is opened, which is
/// what gives both "restart always returns to Normal Mode" (ADR-0006) and "reopening the closed
/// widget returns to Normal Mode" (#42) for free, with no persisted-state path to bypass.
///
/// Reads the target opacity and the avoidance preference from `currentConfig` *at the moment
/// each is needed* rather than capturing them at construction (#46) — that is what makes a
/// settings-panel edit take effect without a restart, and it needs no notification for the
/// common case (the next Ghost Mode entry, the next mouse crossing simply see the new value).
/// `reapplyConfiguration()` covers the one case where nothing else would trigger a re-read: an
/// edit made while already sitting in Ghost Mode.
public final class GhostModeController {
    private let platformOps: PlatformOps
    private let window: WidgetWindowHandle
    private let currentConfig: () -> WidgetConfig
    public private(set) var mode: WidgetMode = .normal
    /// The boss key's (ADR-0012) own bookkeeping: deliberate, persists until deliberately undone
    /// (or until Ghost Mode is left), and never decays on its own.
    private var isHidden = false
    /// Whether the cursor is currently over the widget. Tracked in both modes so entering Ghost
    /// Mode with the mouse already parked on the widget avoids straight away, rather than waiting
    /// for the next crossing.
    private var isMouseInside = false
    /// Mouse-entered avoidance (ADR-0012), on by default. Independent of `isHidden`; read live
    /// from the config so the settings panel's switch applies at the next visibility decision.
    private var isMouseAvoidanceEnabled: Bool { currentConfig().isMouseAvoidanceEnabled }

    public init(platformOps: PlatformOps, window: WidgetWindowHandle, currentConfig: @escaping () -> WidgetConfig) {
        self.platformOps = platformOps
        self.window = window
        self.currentConfig = currentConfig
        platformOps.onMouseInsideChanged(window) { [weak self] inside in
            self?.handleMouseInsideChanged(inside)
        }
    }

    /// Pushes the current config's opacity/avoidance values down right now — for an edit made
    /// *while in Ghost Mode*, where otherwise nothing would happen until the next mode change or
    /// mouse crossing and the user dragging the opacity slider would see no change (#46). A
    /// silent no-op in Normal Mode: the window is opaque there regardless of any setting, and the
    /// platform must not be told to change an opacity it never had.
    public func reapplyConfiguration() {
        guard mode == .ghost else { return }
        applyEffectiveOpacity()
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

    /// Hidden or avoidance → fully invisible; Ghost → its configured target; Normal → opaque.
    /// The single source of the window's visibility, so no two features can disagree about it.
    private var effectiveOpacity: Double {
        guard mode == .ghost else { return 1.0 }
        if isHidden { return 0 }
        return isMouseAvoidanceEnabled && isMouseInside ? 0 : currentConfig().ghostOpacity
    }

    /// Deliberately un-debounced (ADR-0012): whether brushing past the widget's edge actually
    /// flickers is a question for real use, and guessing at it now would bake in a third
    /// sub-state nobody can see.
    private func handleMouseInsideChanged(_ inside: Bool) {
        guard isMouseInside != inside else { return }
        isMouseInside = inside
        guard mode == .ghost, isMouseAvoidanceEnabled else { return }
        applyEffectiveOpacity()
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
