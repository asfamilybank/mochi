import AppKit
import WebKit

/// A Popup Window (#67, ADR-0017, CONTEXT.md): the temporary child window a page opens with
/// `window.open` — typically an OAuth login — and depends on via `window.opener`.
///
/// - Its web view is built from the configuration WebKit hands to `createWebViewWith`, which is
///   what shares the widget's website data (cookies, login state) and keeps `window.opener`
///   wired up; WebKit loads the request into it itself.
/// - An ordinary titled window: the page title in the title bar, a read-only address strip on top
///   (so the user can see which site is asking for their password), no toolbar, no address
///   editing, no Ghost Mode, no persisted geometry.
/// - Sized from `WKWindowFeatures` (500×600 when the page names no size), centered on the widget.
/// - Closes when the page calls `window.close()` (`webViewDidClose`), when the user closes it, and
///   when the widget closes (`closePopupWindows(of:)` from the widget's single teardown point).
///
/// The owning widget handle stays the web view's `uiDelegate`, so dialogs, uploads and nested
/// new-window requests go through the same 网页交互请求 seam — dialogs present on this window.
final class PopupWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static let defaultContentSize = NSSize(width: 500, height: 600)
    private static let addressStripHeight: CGFloat = 28

    let window: NSWindow
    let webView: WKWebView
    private let addressLabel: NSTextField
    private weak var owner: AppKitWidgetWindowHandle?
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, windowFeatures: WKWindowFeatures, owner: AppKitWidgetWindowHandle) {
        self.owner = owner
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        addressLabel = NSTextField(labelWithString: "")
        addressLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addressLabel.textColor = .secondaryLabelColor
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.isSelectable = true
        addressLabel.alignment = .center
        addressLabel.setAccessibilityLabel("网址")
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // The strip sits above the web view, never on top of it — anything layered over a
        // `WKWebView` makes WebKit treat it as occluded and stop painting.
        let contentView = NSView()
        contentView.addSubview(addressLabel)
        contentView.addSubview(separator)
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            addressLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            addressLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            addressLabel.centerYAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Self.addressStripHeight / 2),
            separator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.addressStripHeight),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // A page asking for a sliver of a window (`width=0`) gets one big enough to use.
        let pageSize = NSSize(
            width: max(windowFeatures.width.map { CGFloat($0.doubleValue) } ?? Self.defaultContentSize.width, 200),
            height: max(windowFeatures.height.map { CGFloat($0.doubleValue) } ?? Self.defaultContentSize.height, 150))
        window = NSWindow(
            contentRect: NSRect(
                origin: .zero, size: NSSize(width: pageSize.width, height: pageSize.height + Self.addressStripHeight + 1)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        // Owned through ARC by the widget handle's `popupWindows`, like the widget's own window.
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        window.title = ""
        super.init()

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = owner
        // The per-web-view settings the widget's web view gets (#70, #72), mirrored from it so a
        // popup opened under the current settings behaves like the widget. `preferences` may be
        // a copy of the opener's, so it is set explicitly rather than assumed shared.
        applySettings(from: owner)
        window.setFrame(Self.centeredFrame(window.frame, on: owner.window), display: false)
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in self?.updateTitle() },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in self?.updateAddress() },
        ]
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    /// Copies the widget's live per-web-view settings — called on creation and whenever the
    /// widget's own are pushed again (`reapplyConfiguration`).
    func applySettings(from owner: AppKitWidgetWindowHandle) {
        let ownerPreferences = owner.webView.configuration.preferences
        webView.configuration.preferences.minimumFontSize = ownerPreferences.minimumFontSize
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically =
            ownerPreferences.javaScriptCanOpenWindowsAutomatically
        webView.isInspectable = owner.webView.isInspectable
    }

    /// Closes the window; `windowWillClose` does the teardown.
    func close() {
        window.close()
    }

    private func updateTitle() {
        let title = webView.title ?? ""
        window.title = title.isEmpty ? (webView.url?.host() ?? "") : title
    }

    private func updateAddress() {
        addressLabel.stringValue = webView.url?.absoluteString ?? ""
        addressLabel.toolTip = addressLabel.stringValue
        updateTitle()
    }

    /// Centered on the widget's frame, then pulled fully onto the widget's screen.
    private static func centeredFrame(_ frame: NSRect, on ownerWindow: NSWindow) -> NSRect {
        let ownerFrame = ownerWindow.frame
        var result = frame
        result.origin.x = ownerFrame.midX - frame.width / 2
        result.origin.y = ownerFrame.midY - frame.height / 2
        guard let visible = (ownerWindow.screen ?? NSScreen.main)?.visibleFrame else { return result }
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    // MARK: NSWindowDelegate

    /// Every way out — the red button, `window.close()`, the widget closing — lands here.
    func windowWillClose(_ notification: Notification) {
        observations = []
        // A dialog or Open panel still up on this window must answer WebKit (as a cancel).
        for sheet in window.sheets {
            window.endSheet(sheet, returnCode: .cancel)
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        // Released a turn later: dropping the last reference to this controller (and so to the
        // window) from inside the window's own close would free it while AppKit is still closing it.
        DispatchQueue.main.async { [owner] in
            owner?.popupWindowDidClose(self)
        }
    }

    // MARK: WKNavigationDelegate

    /// The same policy the widget's own navigations get: a ⌘-clicked link goes through the
    /// new-window seam (#67), and the HTTP warning (#72) is read live from the widget.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if let decision = owner?.commandClickDecision(for: navigationAction, in: webView), decision != .loadInOpener {
            return decisionHandler(.cancel, preferences)
        }
        let warns = owner?.isHTTPWarningEnabled ?? false
        preferences.preferredHTTPSNavigationPolicy = warns ? .userMediatedFallbackToHTTP : .keepAsRequested
        decisionHandler(.allow, preferences)
    }
}
