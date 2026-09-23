import Foundation

/// Keeps `NSWindow.title` (Mission Control/Cmd-Tab, #18) following the current page's title,
/// falling back to the loaded URL's host and finally to `"Mochi"` (`AddressFieldPresenter.
/// windowTitle`) so the window is never left with a blank title. Owns exactly this one
/// decision — the Smart Address Field's own text (which also factors in hover/edit/loading
/// state) is a separate, AppKit-local concern per ADR-0009. Constructed once per widget window,
/// mirroring `GhostModeController`'s ownership pattern.
public final class AddressBarController {
    private let platformOps: PlatformOps
    private let window: WidgetWindowHandle
    private var pageTitle: String?
    private var host: String?
    /// While the Empty Page is up, the page behind it (still held for forward) keeps its title
    /// and host here, so forward can put them straight back.
    private var isShowingEmptyPage = false

    public init(platformOps: PlatformOps, window: WidgetWindowHandle) {
        self.platformOps = platformOps
        self.window = window
        platformOps.onPageTitleChanged(window) { [weak self] title in
            self?.pageTitle = title
            self?.updateWindowTitle()
        }
        platformOps.onEmptyPageVisibilityChanged(window) { [weak self] visible in
            self?.isShowingEmptyPage = visible
            self?.updateWindowTitle()
        }
        updateWindowTitle()
    }

    /// Called whenever the widget navigates to a new URL. Clears the previous page's title —
    /// without this, the window title would keep showing the *old* page's title (rather than
    /// falling back to the new host) until the new page's own title happens to arrive.
    public func urlLoaded(_ url: URL) {
        pageTitle = nil
        host = url.host
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        let title = isShowingEmptyPage
            ? AddressFieldPresenter.windowTitle(pageTitle: nil, host: nil)
            : AddressFieldPresenter.windowTitle(pageTitle: pageTitle, host: host)
        platformOps.setWindowTitle(title, in: window)
    }
}
