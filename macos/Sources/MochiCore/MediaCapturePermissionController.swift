import Foundation

/// 网页权限 for one open widget (#101, ADR-0027): decides each camera/microphone request from the
/// widget's page and its Popup Windows, turns the user's answer to Mochi's prompt into a website
/// exception or a 「仅这次允许」 grant, and ends a web view's grants when it loads a new document.
///
/// One per widget window (`Orchestrator.openWidget`), so a reopened widget starts with no grants.
/// The config, the mode and the clock are read at the moment of use, never cached; exceptions are
/// written back through the same `persist` transform every other writer uses.
final class MediaCapturePermissionController {
    private let platformOps: PlatformOps
    private let window: WidgetWindowHandle
    private let currentConfig: () -> WidgetConfig
    private let persist: (@escaping (WidgetConfig) -> WidgetConfig) -> Void
    private let doNotDisturb: () -> Bool
    private let now: () -> Date
    /// 「仅这次允许」, per web view — the in-memory half of the answer, never written to the config.
    private var grantsThisTime: [WebViewSource: Set<MediaCaptureGrant>] = [:]

    init(
        platformOps: PlatformOps, window: WidgetWindowHandle,
        currentConfig: @escaping () -> WidgetConfig,
        persist: @escaping (@escaping (WidgetConfig) -> WidgetConfig) -> Void,
        doNotDisturb: @escaping () -> Bool,
        now: @escaping () -> Date
    ) {
        self.platformOps = platformOps
        self.window = window
        self.currentConfig = currentConfig
        self.persist = persist
        self.doNotDisturb = doNotDisturb
        self.now = now
        platformOps.onMediaCaptureRequested(window) { [weak self] request in
            self?.decide(request) ?? .deny
        }
        platformOps.onMediaCapturePromptAnswered(window) { [weak self] request, answer in
            self?.answer(answer, to: request) ?? false
        }
        platformOps.onNewDocumentCommitted(window) { [weak self] source in
            self?.newDocumentCommitted(in: source)
        }
    }

    private func newDocumentCommitted(in source: WebViewSource) {
        grantsThisTime[source] = nil
        // #96: WebKit's own grant would outlive the page load otherwise — a page reloading itself
        // is never asked again. The old document is gone: nothing to interrupt. This is also where a
        // settings edit taking a grant away reaches a page that already had it: a page load keeps
        // what it was granted, as a running app keeps a system permission revoked in System
        // Settings until it is reopened (ADR-0027). Nothing is forgotten on the edit itself.
        platformOps.forgetMediaCaptureGrants(in: window, of: source, onlyIfIdle: false)
    }

    /// #96: 不打扰 (Ghost Mode) denies the widget's page, so a grant WebKit kept from Normal Mode
    /// must go (a capture already running carries on).
    func doNotDisturbBegan() {
        platformOps.forgetMediaCaptureGrants(in: window, of: .widget, onlyIfIdle: true)
    }

    private func decide(_ request: MediaCaptureRequest) -> MediaCaptureDecision {
        .deciding(
            request, config: currentConfig(), doNotDisturb: doNotDisturb(),
            grantedThisTime: grantsThisTime[request.source] ?? [])
    }

    /// The choice applies to every permission the request needed — both, for a camera+microphone
    /// request. A host-less page has nothing to remember it under: its answer covers this request.
    private func answer(_ answer: MediaCapturePromptAnswer, to request: MediaCaptureRequest) -> Bool {
        let permissions = request.device.pagePermissions
        switch answer {
        case .allowOnThisSite:
            remember(.allow, for: permissions, of: request.host)
            return true
        case .allowThisTime:
            if let host = request.host {
                grantsThisTime[request.source, default: []]
                    .formUnion(permissions.map { MediaCaptureGrant(host: host, permission: $0) })
            }
            return true
        case .deny:
            remember(.deny, for: permissions, of: request.host)
            return false
        }
    }

    private func remember(
        _ setting: WidgetConfig.MediaCapturePermission, for permissions: [PagePermission], of host: String?
    ) {
        guard let host else { return }
        let modifiedAt = now()
        persist { config in
            permissions.reduce(config) {
                $0.updatingPagePermissionException($1, host: host, setting: setting, modifiedAt: modifiedAt)
            }
        }
    }
}
