import Foundation

/// Drives Hotkey Forwarding (#11, ADR-0003): on every press of a configured mapping's trigger,
/// either forwards its `pageKeystroke` into the widget's page (only while Ghost Mode is active,
/// per the domain doc) or guides the user through the one-time Accessibility permission
/// onboarding — never failing silently, per #11's AC.
///
/// Since #46 this type no longer registers the triggers itself: every global hotkey Mochi holds —
/// the two action hotkeys and every mapping trigger — is registered by `Orchestrator` at launch
/// and re-registered live by `SettingsController` on edit, all dispatching through
/// `Orchestrator.handleGlobalHotkeyPressed`, which resolves the pressed combo against the
/// *current* config and hands the mapped page keystroke here. That single dispatch path is what
/// lets an edited mapping take effect without a restart.
///
/// A pure orchestration class exactly like `GhostModeController`: it only talks to `PlatformOps`,
/// never AppKit/CGEvent directly, so it can be exercised against `FakePlatformOps` in tests.
public final class HotkeyForwarder {
    private let platformOps: PlatformOps
    private let isGhostModeActive: () -> Bool
    private var hasPromptedForAccessibility = false

    /// - Parameter isGhostModeActive: queried on every trigger — Hotkey Forwarding only takes
    ///   effect in Ghost Mode (CONTEXT.md), so this stays a closure rather than a one-time
    ///   snapshot to reflect the live mode at press time.
    public init(platformOps: PlatformOps, isGhostModeActive: @escaping () -> Bool) {
        self.platformOps = platformOps
        self.isGhostModeActive = isGhostModeActive
    }

    public func forward(_ pageKeystroke: Hotkey) {
        guard isGhostModeActive() else { return }
        guard platformOps.isAccessibilityTrusted() else {
            if !hasPromptedForAccessibility {
                hasPromptedForAccessibility = true
                platformOps.requestAccessibilityPermission()
            }
            platformOps.presentAlert(
                title: "需要辅助功能权限",
                message: "热键传递功能需要辅助功能权限才能工作，请前往系统设置 → 隐私与安全性 → 辅助功能，允许 Mochi 使用该功能。"
            )
            return
        }
        platformOps.forwardKeystroke(pageKeystroke)
    }
}
