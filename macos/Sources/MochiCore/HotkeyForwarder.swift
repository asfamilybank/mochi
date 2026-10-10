import Foundation

/// Drives Hotkey Forwarding (#11): on every press of a configured mapping's trigger, forwards its
/// `pageKeystroke` into the widget's page — only while Ghost Mode is active, per the domain doc.
/// Since #93 (ADR-0025) the keystroke is handed straight to the widget's web view rather than
/// posted through the system, so there is no Accessibility permission to check or ask for here;
/// a mapping set off by a tap or double tap still needs it, but for *hearing* the trigger, which
/// is `VideoControl`'s to ask for.
///
/// Since #46 this type no longer registers the triggers itself: every global hotkey Mochi holds —
/// the two action hotkeys and every mapping trigger — is registered by `Orchestrator` at launch
/// and re-registered live by `SettingsController` on edit, all dispatching through
/// `Orchestrator.handleGlobalHotkeyPressed`, which resolves the pressed combo against the
/// *current* config and hands the mapped page keystroke here. That single dispatch path is what
/// lets an edited mapping take effect without a restart.
///
/// A pure orchestration class exactly like `GhostModeController`: it only talks to `PlatformOps`,
/// never AppKit directly, so it can be exercised against `FakePlatformOps` in tests.
public final class HotkeyForwarder {
    private let platformOps: PlatformOps
    private let isGhostModeActive: () -> Bool
    private let currentWindow: () -> WidgetWindowHandle?

    /// - Parameters:
    ///   - isGhostModeActive: queried on every trigger — Hotkey Forwarding only takes effect in
    ///     Ghost Mode (CONTEXT.md), so this stays a closure rather than a one-time snapshot to
    ///     reflect the live mode at press time.
    ///   - currentWindow: the widget whose page receives the keystroke, read at press time too.
    public init(
        platformOps: PlatformOps,
        isGhostModeActive: @escaping () -> Bool,
        currentWindow: @escaping () -> WidgetWindowHandle?
    ) {
        self.platformOps = platformOps
        self.isGhostModeActive = isGhostModeActive
        self.currentWindow = currentWindow
    }

    public func forward(_ pageKeystroke: Hotkey) {
        guard isGhostModeActive(), let window = currentWindow() else { return }
        platformOps.forwardKeystroke(pageKeystroke, in: window)
    }
}
