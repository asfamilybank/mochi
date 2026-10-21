import Foundation

/// 隐藏时也从 Dock 和 ⌘Tab 中移除 (#152, ADR-0035): keeps Mochi out of the Dock and ⌘Tab — the
/// two only go together — for as long as `wantsHidden` says so, which `Orchestrator` defines as
/// "the setting is on and the widget is Hidden".
///
/// Switching more often than about once a second leaves duplicate Dock icons behind that outlive
/// the process (measured, `.app` bundle included). So after each real switch comes a one-second
/// cooldown: changes asked for meanwhile are not applied one by one, and when it ends Mochi
/// switches only if what is wanted then differs from where it is. Hiding the window never waits
/// for this — only the Dock icon may lag, by at most the cooldown.
final class DockPresence {
    static let cooldown: TimeInterval = 1

    private let platformOps: PlatformOps
    private let wantsHidden: () -> Bool
    private var isHidden = false
    /// Cancels the running cooldown; `nil` when none is running.
    private var cancelCooldown: (() -> Void)?

    init(platformOps: PlatformOps, wantsHidden: @escaping () -> Bool) {
        self.platformOps = platformOps
        self.wantsHidden = wantsHidden
    }

    /// Brings the Dock and ⌘Tab in line with `wantsHidden` — now, or when the cooldown ends.
    func refresh() {
        guard cancelCooldown == nil else { return }
        let wanted = wantsHidden()
        guard wanted != isHidden else { return }
        isHidden = wanted
        platformOps.setHiddenFromDockAndAppSwitcher(wanted)
        cancelCooldown = platformOps.schedule(after: Self.cooldown) { [weak self] in
            self?.cancelCooldown = nil
            self?.refresh()
        }
    }
}
