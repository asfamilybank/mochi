import Foundation

/// Back/forward with the Empty Page (#16) as a virtual first history entry.
///
/// The Empty Page is native content, not a document, so `WKWebView`'s back-forward list knows
/// nothing about it: once the first page is loaded, that page is the bottom of the list and back
/// is disabled — there was no way to get back to where the session started. This slots the Empty
/// Page underneath the web view's own history, but only for a session that actually *started*
/// on it; a session that started on a URL never had an Empty Page to return to.
///
/// WebKit can't have entries inserted or removed, so the Empty Page stays strictly *below* the
/// web view's list. Going back to it and then typing a new address loads that page on top of
/// whatever the web view last showed — so from the new page, back walks through the web view's
/// history first and reaches the Empty Page last.
public enum EmptyPageHistory {
    public enum Step: Equatable {
        /// The web view's own `goBack()`/`goForward()`.
        case webView
        /// Back from the oldest page onto the Empty Page.
        case toEmptyPage
        /// Forward from the Empty Page onto the page it was left for.
        case fromEmptyPage
    }

    /// `nil` means back is disabled.
    public static func backStep(
        isShowingEmptyPage: Bool, startedOnEmptyPage: Bool, webViewCanGoBack: Bool
    ) -> Step? {
        if isShowingEmptyPage { return nil }
        if webViewCanGoBack { return .webView }
        return startedOnEmptyPage ? .toEmptyPage : nil
    }

    /// `nil` means forward is disabled.
    /// - Parameter hasPage: whether anything was ever loaded — the page forward returns to.
    public static func forwardStep(
        isShowingEmptyPage: Bool, hasPage: Bool, webViewCanGoForward: Bool
    ) -> Step? {
        if isShowingEmptyPage { return hasPage ? .fromEmptyPage : nil }
        return webViewCanGoForward ? .webView : nil
    }
}
