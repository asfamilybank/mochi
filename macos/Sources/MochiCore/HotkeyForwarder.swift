import Foundation

/// Drives Hotkey Forwarding (#11, ADR-0003): registers each configured `HotkeyMapping`'s
/// `trigger` as a global hotkey, and on every press either forwards `pageKeystroke` into the
/// widget's page (only while Ghost Mode is active, per the domain doc) or guides the user through
/// the one-time Accessibility permission onboarding — never failing silently, per #11's AC.
///
/// A pure orchestration class exactly like `GhostModeController`: it only talks to `PlatformOps`,
/// never AppKit/CGEvent directly, so it can be exercised against `FakePlatformOps` in tests.
public final class HotkeyForwarder {
    private let platformOps: PlatformOps
    private let isGhostModeActive: () -> Bool
    private var hasPromptedForAccessibility = false

    /// - Parameters:
    ///   - reservedTriggers: combos already claimed by `Orchestrator`'s default hotkeys (#12).
    ///     A mapping whose `trigger` is in this set is skipped rather than registered — Carbon's
    ///     `RegisterEventHotKey` happily accepts the same combo registered twice in-process, which
    ///     would make both handlers fire on every press (a page-forwarded keystroke *and* the
    ///     default action) instead of surfacing as a conflict.
    ///   - isGhostModeActive: queried on every trigger — Hotkey Forwarding only takes effect in
    ///     Ghost Mode (CONTEXT.md), so this stays a closure rather than a one-time snapshot to
    ///     reflect the live mode at press time.
    public init(
        platformOps: PlatformOps, mappings: [HotkeyMapping], reservedTriggers: Set<Hotkey> = [],
        isGhostModeActive: @escaping () -> Bool
    ) {
        self.platformOps = platformOps
        self.isGhostModeActive = isGhostModeActive

        var conflictCount = 0
        for mapping in mappings {
            guard !reservedTriggers.contains(mapping.trigger) else {
                conflictCount += 1
                continue
            }
            let registered = platformOps.registerGlobalHotkey(mapping.trigger) { [weak self] in
                self?.handleTriggered(mapping.pageKeystroke)
            }
            if !registered {
                conflictCount += 1
            }
        }
        if conflictCount > 0 {
            platformOps.presentAlert(
                title: "热键映射注册失败",
                message: "\(conflictCount) 条热键映射的触发热键已被其他应用或 Mochi 自身的默认热键占用，请检查冲突后调整映射。"
            )
        }
    }

    private func handleTriggered(_ pageKeystroke: Hotkey) {
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
