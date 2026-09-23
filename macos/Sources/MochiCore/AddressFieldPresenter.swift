import Foundation

/// The Smart Address Field's (#18) display decision — framework-agnostic so it can be unit
/// tested without AppKit. All of its inputs (loading state, hover/focus, the page's title/URL/
/// host) are AppKit-local state the view code (`AppKitWidgetWindowHandle`) already owns via
/// `WKWebView` KVO and its own `NSTrackingArea`/`NSTextFieldDelegate` tracking — this type is
/// fed those values directly rather than through `PlatformOps`. The Empty Page (#16) runs through
/// here too: with no URL, title or host, every non-editing state resolves to an empty text, which
/// leaves the field showing its placeholder as a display until clicked.
public enum AddressFieldPresenter {
    public struct DisplayState: Equatable {
        public let text: String
        public let isEditable: Bool

        public init(text: String, isEditable: Bool) {
            self.text = text
            self.isEditable = isEditable
        }
    }

    /// - Parameter isEditing: highest priority — the user has clicked in and not yet blurred/
    ///   submitted, so the field is an editable `urlString` even mid-load. It used to rank below
    ///   `isLoading`, which meant a heavy page left the address bar unclickable for as long as it
    ///   kept loading (measured: ~20s on a real site); every other browser lets you retype an
    ///   address while the current one is still coming in.
    /// - Parameter isLoading: shows `urlString` read-only while nobody is editing — so a
    ///   navigation in flight is always legible as the URL it is fetching, not the old title.
    /// - Parameter isHovering: the mouse is over the field without having clicked — shows a
    ///   read-only `urlString`.
    /// - Parameter pageTitle: falls back to `host`, then an empty string, when idle.
    public static func displayState(
        isLoading: Bool,
        isHovering: Bool,
        isEditing: Bool,
        pageTitle: String?,
        urlString: String,
        host: String?
    ) -> DisplayState {
        if isEditing {
            return DisplayState(text: urlString, isEditable: true)
        }
        if isLoading {
            return DisplayState(text: urlString, isEditable: false)
        }
        if isHovering {
            return DisplayState(text: urlString, isEditable: false)
        }
        return DisplayState(text: nonEmpty(pageTitle) ?? nonEmpty(host) ?? "", isEditable: false)
    }

    /// Whether a page-driven update (a title/URL/loading KVO tick, a hover enter/exit) may still
    /// rewrite the field. A live editing session outranks every one of them: from the moment the
    /// field holds a field editor until it loses it, the text belongs to whoever is typing, and
    /// re-deriving it from `displayState` would wipe a half-typed address out from under them —
    /// which is exactly what a page that keeps loading in the background, or a mouse that drifts
    /// off the field mid-word, used to do. `displayState`'s own inputs are unchanged; this is the
    /// question of *whether to ask it at all*.
    public static func acceptsPageDrivenUpdates(hasActiveEditingSession: Bool) -> Bool {
        !hasActiveEditingSession
    }

    /// Whether the Smart Address Field's trailing embedded refresh affordance (#27) is shown.
    /// Hidden on the Empty Page — before any real navigation there is nothing to reload, matching
    /// that state's existing "no independent URL input" spirit — and shown from the first
    /// navigation onward — except while the field is being edited: the address being typed is
    /// not the page refresh would reload, and the room goes to the text instead. Deliberately
    /// *not* a loading/stop toggle (ADR-0011): the icon means "refresh" in every state, so
    /// `isLoading` is not an input here.
    public static func showsEmbeddedRefreshIcon(hasNavigatedAtLeastOnce: Bool, isEditing: Bool) -> Bool {
        hasNavigatedAtLeastOnce && !isEditing
    }

    /// `NSWindow.title`'s fallback chain (#18) — one level deeper than the address field's own
    /// default display, since a window title must never end up empty (Mission Control/Cmd-Tab).
    public static func windowTitle(pageTitle: String?, host: String?) -> String {
        nonEmpty(pageTitle) ?? nonEmpty(host) ?? "Mochi"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
