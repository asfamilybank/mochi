import Foundation

/// What the widget window should show when the app launches (#16) — either a real page or the
/// native Empty Page. Kept as its own type rather than folded into `WidgetConfig` since resolving
/// it is a decision made from several fields, not data the config itself stores.
public enum StartupContent: Equatable {
    case url(URL)
    case emptyPage
}

public enum StartupResolution {
    /// Decision rule: an explicit `startupTarget` (set via the settings panel's tri-state
    /// selector, #13) always wins. With none set, falls back to the last-visited `url` if there is
    /// one, or the Empty Page if there's never been any browsing history at all — the "fresh
    /// install, nothing configured or navigated yet" case `AppDelegate` hits before `url` has ever
    /// been written. A pure function — never touches `PlatformOps` — so `Orchestrator.start` is
    /// the only place that acts on its result.
    public static func resolveStartupContent(for config: WidgetConfig) -> StartupContent {
        switch config.startupTarget {
        case .url(let url):
            return .url(url)
        case .emptyPage:
            return .emptyPage
        case nil:
            if let url = config.url {
                return .url(url)
            }
            return .emptyPage
        }
    }
}
