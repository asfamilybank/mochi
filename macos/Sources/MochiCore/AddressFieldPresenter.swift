import Foundation

/// The Smart Address Field's (#18) display decision — framework-agnostic so it can be unit
/// tested without AppKit. All of its inputs (loading state, hover/focus, the page's title/URL/
/// host) are AppKit-local state the view code (`AppKitWidgetWindowHandle`) already owns via
/// `WKWebView` KVO and its own `NSTrackingArea`/`NSSearchFieldDelegate` tracking — this type is
/// fed those values directly rather than through `PlatformOps`. This only covers the address
/// field's state *after* a real navigation has happened — the Empty Page's fixed placeholder
/// (#16) is a separate, untouched code path.
public enum AddressFieldPresenter {
    public struct DisplayState: Equatable {
        public let text: String
        public let isEditable: Bool

        public init(text: String, isEditable: Bool) {
            self.text = text
            self.isEditable = isEditable
        }
    }

    /// - Parameter isLoading: highest priority — while `true`, `urlString` is shown regardless of
    ///   `isHovering`/`isEditing`.
    /// - Parameter isEditing: the user has clicked in and not yet blurred/submitted — shows an
    ///   editable `urlString`.
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
        if isLoading {
            return DisplayState(text: urlString, isEditable: false)
        }
        if isEditing {
            return DisplayState(text: urlString, isEditable: true)
        }
        if isHovering {
            return DisplayState(text: urlString, isEditable: false)
        }
        return DisplayState(text: nonEmpty(pageTitle) ?? nonEmpty(host) ?? "", isEditable: false)
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
