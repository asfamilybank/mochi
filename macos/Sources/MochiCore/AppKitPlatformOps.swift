import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import WebKit

/// Bridges `DesignTokens`/`DesignIcon` (framework-agnostic value types) into the AppKit types
/// the toolbar draws with. Kept separate from `DesignTokens.swift` itself so that module stays
/// free of AppKit-specific rendering concerns beyond accent-color resolution.
private enum ToolbarStyle {
    /// A color that re-resolves its light/dark RGBA at draw time, the same mechanism system
    /// dynamic colors (like `NSColor.controlAccentColor`) use — so callers get correct
    /// appearance-switching for free wherever AppKit resolves `NSColor` at render time
    /// (`contentTintColor`, `tintColor`, `textColor`, `backgroundColor`).
    static func dynamicColor(light: DesignTokens.RGBA, dark: DesignTokens.RGBA) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgba: isDark ? dark : light)
        }
    }

    static func iconTint() -> NSColor {
        dynamicColor(light: DesignTokens.glassPalette(dark: false).iconPrimary, dark: DesignTokens.glassPalette(dark: true).iconPrimary)
    }

    /// Renders a `DesignIcon`'s path as a stroked template image (uniform stroke weight, round
    /// caps/joins — matching `DesignIcon`'s own documented SF Symbols-style geometry), so
    /// `NSButton.contentTintColor` can tint it like any system template image.
    static func templateImage(for icon: DesignIcon, accessibilityDescription: String) -> NSImage {
        let gridSize: CGFloat = 24
        let image = NSImage(size: NSSize(width: gridSize, height: gridSize), flipped: true) { _ in
            let bezier = NSBezierPath(cgPath: icon.path)
            bezier.lineWidth = CGFloat(DesignTokens.Layout.iconStrokeWidth)
            bezier.lineCapStyle = .round
            bezier.lineJoinStyle = .round
            NSColor.black.setStroke()
            bezier.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}

private extension NSColor {
    convenience init(rgba: DesignTokens.RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}

/// Reserves room at the trailing edge of the address field's text area for its embedded refresh
/// affordance (ADR-0011), so a long title/URL truncates before it reaches the icon instead of
/// sliding underneath it. `NSSearchField` exposes no view-level hook for that geometry — the cell
/// owns it — which is why this is a cell subclass rather than a layout tweak on the field.
private final class AddressFieldCell: NSSearchFieldCell {
    /// Points shaved off the trailing edge of the text area; `0` while the icon is hidden.
    var trailingInset: CGFloat = 0

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.searchTextRect(forBounds: rect)
        textRect.size.width = max(0, textRect.width - trailingInset)
        return textRect
    }
}

/// A search field that reports the moment it's clicked, *before* AppKit's own `mouseDown`
/// processing runs — needed so the Smart Address Field (#18) can flip into its editable state
/// (`AddressFieldPresenter`) in time for that same click to place a cursor, rather than the user
/// needing a second click after the field becomes editable.
private final class AddressField: NSSearchField {
    var onMouseDown: (() -> Void)?

    /// `NSControl` builds its cell from this at `init(frame:)` time — the only way to get
    /// `AddressFieldCell`'s text-rect inset in without swapping a live `cell` out from under
    /// `NSSearchField`.
    override class var cellClass: AnyClass? {
        get { AddressFieldCell.self }
        set {}
    }

    /// Drops the horizontal half of `NSTextField`'s content-derived intrinsic width, which the
    /// field only reports once it actually holds text. `NSToolbarItem` derives its own `maxSize`
    /// from the hosted view, and a present horizontal intrinsic makes it collapse that maximum
    /// onto the fitting size — so without this the field is elastic between its min and max on
    /// the Empty Page and then freezes at its *minimum* width from the first navigation onward
    /// (measured, ADR-0011). The field's width is decided entirely by its own min/max constraints
    /// plus how much room the toolbar has; its text should never be an input to that.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

/// The back/forward segmented control's segment indices (ADR-0011) — shared between the factory
/// that builds the control and the handle that enables and dispatches its segments.
private enum NavigationSegment {
    static let back = 0
    static let forward = 1
}

/// Reports hover enter/exit for a single view via its own `NSTrackingArea`, decoupled from the
/// window-wide tracking area `installGhostModeMouseTracking` installs for Ghost Mode — each
/// `NSTrackingArea` needs a distinct `owner` for AppKit to route enter/exit callbacks separately.
private final class HoverTracker: NSObject {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    @objc func mouseEntered(with event: NSEvent) { onEnter?() }
    @objc func mouseExited(with event: NSEvent) { onExit?() }
}

/// The interactive controls hosted in the Normal Mode `NSToolbar` (ADR-0009). Bundled together
/// because they're always constructed, wired, and handed off as one unit.
fileprivate struct ToolbarControls {
    /// Back and forward as one joined native control (ADR-0011), not two independent buttons.
    let navigationControl: NSSegmentedControl
    let addressField: AddressField
    /// The refresh affordance embedded at `addressField`'s trailing edge (ADR-0011) — a subview
    /// of the field, not a toolbar item of its own the way it used to be.
    let addressFieldRefreshButton: NSButton
}

/// The Loading Progress Bar (#18): a thin line docked to the content area's top edge, overlaid
/// on top of `webView`/the Empty Page rather than reserving its own layout row — matching
/// design-language.md's "不加载时不占用界面空间". `widthConstraint`'s `constant` is driven
/// straight from `WKWebView.estimatedProgress`.
fileprivate struct LoadingProgressBar {
    let view: NSView
    let widthConstraint: NSLayoutConstraint
}

/// Normal Mode's window chrome (ADR-0009, refined by ADR-0011): a native `NSToolbar` in
/// `.unified` style — traffic lights, a back/forward segmented control, the Smart Address
/// Field (with refresh embedded at its trailing edge), and settings all on one row, rendered
/// with the system's own Liquid Glass material — sitting above the WKWebView. No title text is
/// drawn next to the traffic lights (`titleVisibility = .hidden`), and settings collapses into
/// the system's overflow menu as the window narrows (`NSToolbarItem.visibilityPriority`).
///
/// Colors, corner radii, spacing, and the bespoke vector icon set all come from `DesignTokens`/
/// `DesignIcon` (#17) — nothing here writes its own numbers.
final class AppKitWidgetWindowHandle: NSObject, WidgetWindowHandle, NSWindowDelegate, NSSearchFieldDelegate, WKNavigationDelegate {
    private static let navigationItemID = NSToolbarItem.Identifier("com.mochi.toolbar.navigation")
    private static let addressItemID = NSToolbarItem.Identifier("com.mochi.toolbar.address")
    private static let settingsItemID = NSToolbarItem.Identifier("com.mochi.toolbar.settings")
    /// The Normal Mode toolbar's fixed item order (`DesignTokens.normalModeToolbarOrder`, minus
    /// the not-yet-implemented Ghost Mode toggle button — see AppKitPlatformOps's doc comment).
    /// Three items of our own: back and forward share one segmented control, and refresh is
    /// embedded in the address field rather than being an item of its own (ADR-0011).
    ///
    /// The single `.flexibleSpace` is what makes the address field's bounded width read correctly
    /// (ADR-0011): once the field stops stretching to fill everything left over, the slack has to
    /// go somewhere, and parking all of it between the field and the trailing button keeps that
    /// button flush with the window's trailing edge. Without it the whole row packs to the left
    /// and leaves a dead gap after the settings button. Still true now that Pin is gone
    /// (ADR-0012) and settings is the only trailing item.
    private static let toolbarItemOrder: [NSToolbarItem.Identifier] = [
        navigationItemID, addressItemID, .flexibleSpace, settingsItemID,
    ]

    /// Width the embedded refresh icon claims from the address field's text area — the icon plus
    /// the padding on either side of it.
    private static let embeddedRefreshIconReservedWidth =
        DesignTokens.Layout.addressFieldEmbeddedIconDiameter
            + DesignTokens.Layout.addressFieldEmbeddedIconTrailingPadding * 2

    let window: NSWindow
    let webView: WKWebView
    private let controls: ToolbarControls
    private let progressBar: LoadingProgressBar
    /// The Empty Page's (#16) native content, occupying the same slot as `webView` inside
    /// `contentContainer` — exactly one of the two is visible at a time, toggled by `loadURL`/
    /// `showEmptyPage` rather than swapped in and out of the view hierarchy.
    private let emptyPageHostingView: NSHostingView<EmptyPageView>
    private let addressFieldHoverTracker = HoverTracker()
    private var willCloseHandler: (() -> Void)?
    private var urlSubmittedHandler: ((URL) -> Void)?
    private var settingsRequestedHandler: (() -> Void)?
    private var navigationFinishedHandler: (() -> Void)?
    private var mouseEnteredHandler: (() -> Void)?
    private var pageTitleChangedHandler: ((String?) -> Void)?
    private var loadingStateChangedHandler: ((Bool) -> Void)?
    private var loadingProgressChangedHandler: ((Double) -> Void)?
    /// Whether a real navigation (`loadURL`) has ever happened — the Smart Address Field (#18)
    /// only kicks in once this flips `true`; before that, the Empty Page's (#16) fixed
    /// placeholder + freely-editable field is left untouched (story #12).
    private var hasNavigatedAtLeastOnce = false
    private var isLoading = false
    /// Mirrors `webView.url`, but updated *synchronously* in `loadURL` — `webView.url` itself only
    /// updates once WKWebView actually commits the navigation, which lags a KVO tick or more
    /// behind the `loadURL`/`isLoading` transition, so reading `webView.url` directly in
    /// `updateAddressFieldDisplay()` could show the previous page's (stale) URL/host for a moment.
    private var currentURL: URL?
    private var isHoveringAddressField = false
    private var isEditingAddressField = false
    private let defaultWindowBackgroundColor: NSColor
    private var navigationObservations: [NSKeyValueObservation] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var accentColorObserver: NSObjectProtocol?

    fileprivate init(
        window: NSWindow, webView: WKWebView, controls: ToolbarControls, emptyPageHostingView: NSHostingView<EmptyPageView>, progressBar: LoadingProgressBar
    ) {
        self.window = window
        self.webView = webView
        self.controls = controls
        self.emptyPageHostingView = emptyPageHostingView
        self.progressBar = progressBar
        self.defaultWindowBackgroundColor = window.backgroundColor
        super.init()
        window.delegate = self
        webView.navigationDelegate = self
        installGhostModeMouseTracking()
        installAddressFieldHoverTracking()
        controls.addressField.delegate = self
        controls.addressField.onMouseDown = { [weak self] in
            self?.beginEditingAddressField()
        }
        controls.navigationControl.target = self
        controls.navigationControl.action = #selector(navigationSegmentClicked(_:))
        controls.addressFieldRefreshButton.target = self
        controls.addressFieldRefreshButton.action = #selector(reload)
        observeNavigationState()
        updateEmbeddedRefreshIconVisibility()
        updateProgressBarColor()
        // The progress bar's fill is baked into a CALayer color (not a dynamic NSColor), so unlike
        // everywhere else in this file it needs to be re-applied whenever the system accent color
        // or the window's light/dark appearance changes, instead of re-resolving for free at draw
        // time.
        appearanceObservation = window.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.updateProgressBarColor()
        }
        accentColorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateProgressBarColor()
        }
    }

    deinit {
        if let accentColorObserver {
            NotificationCenter.default.removeObserver(accentColorObserver)
        }
    }

    private func observeNavigationState() {
        setNavigationSegment(NavigationSegment.back, enabled: webView.canGoBack)
        setNavigationSegment(NavigationSegment.forward, enabled: webView.canGoForward)
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.setNavigationSegment(NavigationSegment.back, enabled: change.newValue ?? false)
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.setNavigationSegment(NavigationSegment.forward, enabled: change.newValue ?? false)
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.currentURL = change.newValue ?? self.currentURL
                self.updateAddressFieldDisplay()
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.updateAddressFieldDisplay()
                self.pageTitleChangedHandler?(change.newValue ?? nil)
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                let isLoading = change.newValue ?? false
                self.isLoading = isLoading
                self.updateAddressFieldDisplay()
                self.updateProgressBarVisibility(isLoading: isLoading)
                self.loadingStateChangedHandler?(isLoading)
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                let progress = change.newValue ?? 0
                self.updateProgressBarWidth(progress: progress)
                self.loadingProgressChangedHandler?(progress)
            },
        ]
    }

    /// Unlike the two standalone `NSButton`s this replaced — which had to be hand-tinted between
    /// a muted icon tint to read as disabled — AppKit dims a disabled `NSSegmentedControl`
    /// segment itself, so toggling `isEnabled` is the whole story here.
    private func setNavigationSegment(_ segment: Int, enabled: Bool) {
        controls.navigationControl.setEnabled(enabled, forSegment: segment)
    }

    @objc private func navigationSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case NavigationSegment.back: webView.goBack()
        case NavigationSegment.forward: webView.goForward()
        default: break
        }
    }

    /// Not `private` — the target-action for the Normal Mode toolbar's embedded refresh button,
    /// and called directly by `AppKitPlatformOps.reloadPage(in:)` for the default 刷新页面
    /// hotkey (#12).
    @objc func reload() {
        webView.reload()
    }

    /// Ghost Mode's always-on-top level (ADR-0012). There is no toolbar control or persisted
    /// state behind this any more — `GhostModeController` is the only caller.
    func setPinned(_ pinned: Bool) {
        window.level = pinned ? .floating : .normal
    }

    /// The Loading Progress Bar's fill color, system accent — baked into a `CALayer` (see the
    /// class-level comment), so re-applied on every accent/appearance change.
    private func updateProgressBarColor() {
        progressBar.view.layer?.backgroundColor = NSColor(rgba: DesignTokens.resolveSystemAccent()).cgColor
    }

    private func updateProgressBarVisibility(isLoading: Bool) {
        if isLoading {
            progressBar.widthConstraint.constant = 0
            progressBar.view.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                progressBar.view.animator().alphaValue = 0
            }
        }
    }

    private func updateProgressBarWidth(progress: Double) {
        let containerWidth = window.contentView?.bounds.width ?? 0
        progressBar.widthConstraint.constant = containerWidth * CGFloat(min(max(progress, 0), 1))
    }

    /// Computes and applies the Smart Address Field's (#18) current text + editability via
    /// `AddressFieldPresenter`, using `webView`'s own state directly (no `PlatformOps` round trip
    /// needed — this view already owns `webView`) plus the locally-tracked hover/edit flags. A
    /// no-op before the first real navigation (see `hasNavigatedAtLeastOnce`).
    private func updateAddressFieldDisplay() {
        guard hasNavigatedAtLeastOnce else { return }
        let state = AddressFieldPresenter.displayState(
            isLoading: isLoading,
            isHovering: isHoveringAddressField,
            isEditing: isEditingAddressField,
            pageTitle: webView.title,
            urlString: currentURL?.absoluteString ?? "",
            host: currentURL?.host
        )
        if controls.addressField.stringValue != state.text {
            controls.addressField.stringValue = state.text
        }
        controls.addressField.isEditable = state.isEditable
    }

    /// Shows or hides the address field's embedded refresh affordance (ADR-0011) per
    /// `AddressFieldPresenter`, keeping the text area's trailing inset in step so the two never
    /// overlap. Driven purely by `hasNavigatedAtLeastOnce` — deliberately not by `isLoading`,
    /// since this icon is not a stop/cancel toggle.
    private func updateEmbeddedRefreshIconVisibility() {
        let isVisible = AddressFieldPresenter.showsEmbeddedRefreshIcon(
            hasNavigatedAtLeastOnce: hasNavigatedAtLeastOnce)
        controls.addressFieldRefreshButton.isHidden = !isVisible
        (controls.addressField.cell as? AddressFieldCell)?.trailingInset =
            isVisible ? Self.embeddedRefreshIconReservedWidth : 0
        controls.addressField.needsDisplay = true
    }

    private func installAddressFieldHoverTracking() {
        addressFieldHoverTracker.onEnter = { [weak self] in
            self?.isHoveringAddressField = true
            self?.updateAddressFieldDisplay()
        }
        addressFieldHoverTracker.onExit = { [weak self] in
            self?.isHoveringAddressField = false
            self?.updateAddressFieldDisplay()
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: addressFieldHoverTracker,
            userInfo: nil
        )
        controls.addressField.addTrackingArea(trackingArea)
    }

    /// Flips the field into its editable state (story #4) — called from `AddressField.onMouseDown`
    /// *before* AppKit's own click handling runs, so the same click both reveals the URL and
    /// places a cursor in it, rather than requiring a second click. Excludes `isLoading`: the
    /// presenter forces a non-editable URL display while loading regardless of `isEditing`, so
    /// setting the flag here would just get silently stuck `true` (with no focus ever having been
    /// granted) until the load finishes.
    private func beginEditingAddressField() {
        guard hasNavigatedAtLeastOnce, !isLoading, !isEditingAddressField else { return }
        isEditingAddressField = true
        updateAddressFieldDisplay()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === controls.addressField else { return }
        isEditingAddressField = false
        updateAddressFieldDisplay()
    }

    func setWillCloseHandler(_ handler: @escaping () -> Void) {
        willCloseHandler = handler
    }

    func setURLSubmittedHandler(_ handler: @escaping (URL) -> Void) {
        urlSubmittedHandler = handler
    }

    func setSettingsRequestedHandler(_ handler: @escaping () -> Void) {
        settingsRequestedHandler = handler
    }

    @objc private func handleSettingsRequested() {
        settingsRequestedHandler?()
    }

    func injectScript(_ source: String) {
        webView.evaluateJavaScript(source, completionHandler: nil)
    }

    /// Switches the content area back to `webView` (in case the Empty Page was showing) and loads
    /// `url` into it — used both for the resolved startup URL and every later address-bar
    /// navigation, so navigating away from the Empty Page always brings the page back on top.
    func loadURL(_ url: URL) {
        emptyPageHostingView.isHidden = true
        webView.isHidden = false
        hasNavigatedAtLeastOnce = true
        currentURL = url
        webView.load(URLRequest(url: url))
        updateEmbeddedRefreshIconVisibility()
        updateAddressFieldDisplay()
    }

    /// Switches the content area to the Empty Page's native content, hiding `webView` — the
    /// counterpart to `loadURL`.
    func showEmptyPage() {
        webView.isHidden = true
        emptyPageHostingView.isHidden = false
    }

    func setNavigationFinishedHandler(_ handler: @escaping () -> Void) {
        navigationFinishedHandler = handler
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationFinishedHandler?()
    }

    func setToolbarVisible(_ visible: Bool) {
        window.toolbar?.isVisible = visible
    }

    func windowWillClose(_ notification: Notification) {
        willCloseHandler?()
    }

    func setNativeChromeVisible(_ visible: Bool) {
        if visible {
            window.styleMask.insert(.titled)
        } else {
            window.styleMask.remove(.titled)
        }
    }

    /// `drawsBackground` is a private WKWebView property (ADR-0001) reached via KVC since it has
    /// no public accessor; it must be `false` for anything below full opacity to show through at
    /// all, on top of which `NSWindow.alphaValue` supplies the actual continuous target value.
    ///
    /// This is also how the widget goes fully invisible (`opacity == 0`, ADR-0012): deliberately
    /// `alphaValue = 0` and not `orderOut`, which would let WebKit treat the window as occluded
    /// and throttle the page.
    func setContentOpacity(_ opacity: Double) {
        let isFullyOpaque = opacity >= 1.0
        window.isOpaque = isFullyOpaque
        window.backgroundColor = isFullyOpaque ? defaultWindowBackgroundColor : .clear
        webView.setValue(isFullyOpaque, forKey: "drawsBackground")
        window.alphaValue = CGFloat(opacity)
    }

    func setMousePassthrough(_ enabled: Bool) {
        window.ignoresMouseEvents = enabled
    }

    func setMouseEnteredHandler(_ handler: @escaping () -> Void) {
        mouseEnteredHandler = handler
    }

    func setSnapThreshold(_ threshold: Double) {
        (window as? MochiWidgetWindow)?.snapThreshold = threshold
    }

    /// A tracking area on the whole content view is what lets Ghost Mode detect "mouse moved
    /// into the widget" (#8) even though the window ignores mouse events at the time — AppKit
    /// evaluates tracking-rect enter/exit from raw cursor position, independent of
    /// `ignoresMouseEvents` (which only governs click/scroll dispatch).
    private func installGhostModeMouseTracking() {
        guard let contentView = window.contentView else { return }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(trackingArea)
    }

    @objc private func mouseEntered(with event: NSEvent) {
        mouseEnteredHandler?()
    }

    // Intentionally does nothing on exit — leaving the area does not restore visibility
    // (ADR-0006); only toggling Ghost Mode off does, via `GhostModeController`.
    @objc private func mouseExited(with event: NSEvent) {}

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === controls.addressField, commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        guard let url = Self.resolveURL(from: controls.addressField.stringValue) else { return true }
        urlSubmittedHandler?(url)
        // Blurs the field, which fires `controlTextDidEndEditing` and reverts the display back to
        // the (new) page's title once it loads — matches story #4's "submit closes edit mode".
        window.makeFirstResponder(nil)
        return true
    }

    private static func resolveURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    func setPageTitleChangedHandler(_ handler: @escaping (String?) -> Void) {
        pageTitleChangedHandler = handler
    }

    func setLoadingStateChangedHandler(_ handler: @escaping (Bool) -> Void) {
        loadingStateChangedHandler = handler
    }

    func setLoadingProgressChangedHandler(_ handler: @escaping (Double) -> Void) {
        loadingProgressChangedHandler = handler
    }

    func setWindowTitle(_ title: String) {
        window.title = title
    }
}

extension AppKitWidgetWindowHandle: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarItemOrder
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarItemOrder
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        // `visibilityPriority` is AppKit's own responsive-collapse mechanism (ADR-0011), not
        // custom layout code: as the window narrows, the toolbar sweeps its lowest-priority items
        // into the system's "更多工具栏项" overflow popup first. Since Pin was internalized into
        // Ghost Mode (ADR-0012) settings is the only collapsible item left — a low-frequency,
        // app-level entry point — while the address field and the navigation control sit at
        // `.high` so they are never candidates. `label` is what an item is called once it lands in
        // that menu — it stays invisible in the toolbar itself, which runs in `.iconOnly` display
        // mode.
        switch itemIdentifier {
        case Self.navigationItemID:
            item.view = controls.navigationControl
            item.label = "后退/前进"
            item.visibilityPriority = .high
        case Self.addressItemID:
            item.view = controls.addressField
            item.label = "地址"
            item.visibilityPriority = .high
        case Self.settingsItemID:
            // A stock image+action item rather than a custom view. It was made one so it would
            // shed into the overflow menu *before* Pin (ADR-0011: AppKit sheds a run of adjacent
            // custom-view items in a single step, so two views could never collapse one at a
            // time); Pin is gone now, but leaving this as a stock item keeps the shipped
            // rendering — a stock item has no `contentTintColor` and no fixed box, so this glyph
            // draws at AppKit's own control tint and metrics rather than `DesignTokens`'
            // `iconPrimary`/`normalModeToolbarButtonDiameter`. docs/design-language.md documents
            // this entry as the "更多" (⋯) affordance, hence `.moreHorizontal`.
            item.image = ToolbarStyle.templateImage(for: .moreHorizontal, accessibilityDescription: "设置")
            item.target = self
            item.action = #selector(handleSettingsRequested)
            item.label = "设置"
            item.visibilityPriority = .low
        default:
            return nil
        }
        return item
    }
}

/// Backs live drag snapping (#6) via `constrainFrameRect`, which AppKit itself calls throughout
/// an interactive title-bar drag to decide where the window is allowed to land (the same hook it
/// uses internally to keep dragged windows on-screen). Snapping here — inside the same call
/// AppKit uses to place the window — means there is exactly one authority deciding the frame per
/// drag step. An earlier approach reacted to `windowDidMove` *after* AppKit had already placed
/// the window, which fought AppKit's own drag loop (each one re-correcting the other) and caused
/// visible jitter during a slow drag; this doesn't have a second authority to fight.
final class MochiWidgetWindow: NSWindow {
    var snapThreshold = WindowSnapping.defaultThreshold

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        // Only snap a pure move — during an active resize the frame's size is still changing,
        // and naively adjusting the origin then would fight the edge the user is dragging.
        guard constrained.size == frame.size else { return constrained }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let snapped = WindowSnapping.snappedFrame(
            WindowFrame(cgRect: constrained), toEdgesOf: screens, threshold: snapThreshold)
        return snapped.cgRect
    }
}

/// Bridges a `TrayMenuItem`'s closure to the `@objc`/target-action mechanism `NSMenuItem`
/// requires. `NSMenuItem.target` doesn't retain its target, so `AppKitPlatformOps` must keep
/// these alive itself for as long as the tray menu exists.
private final class TrayMenuItemTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

public final class AppKitPlatformOps: PlatformOps {
    /// Retains the tray icon's `NSStatusItem` and its menu's `TrayMenuItemTarget`s for as long as
    /// the tray exists — `NSStatusBar` doesn't keep the status item alive on its own, and
    /// `NSMenuItem.target` doesn't retain its target either.
    private var tray: (statusItem: NSStatusItem, targets: [TrayMenuItemTarget])?

    public init() {}

    public func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle {
        let rect = NSRect(x: initialFrame.x, y: initialFrame.y, width: initialFrame.width, height: initialFrame.height)
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false

        let emptyPageHostingView = NSHostingView(rootView: EmptyPageView())
        emptyPageHostingView.translatesAutoresizingMaskIntoConstraints = false
        emptyPageHostingView.isHidden = true

        // `webView` and `emptyPageHostingView` (#16) share this container, each pinned to fill it
        // completely — only one is ever visible at a time (see `loadURL`/`showEmptyPage`).
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(webView)
        contentContainer.addSubview(emptyPageHostingView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            emptyPageHostingView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            emptyPageHostingView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            emptyPageHostingView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            emptyPageHostingView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        let controls = makeToolbarControls()
        let progressBar = makeLoadingProgressBar()

        // The progress bar overlays the top edge of the content area (added after it, so it
        // draws on top) instead of occupying its own row — it takes no layout space while hidden.
        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(contentContainer)
        rootView.addSubview(progressBar.view)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            progressBar.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            progressBar.view.topAnchor.constraint(equalTo: rootView.topAnchor),
        ])

        let window = MochiWidgetWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ADR-0009: traffic lights + toolbar content share one native row, rendered with the
        // system's own Liquid Glass material — no `NSGlassEffectView` wrapper needed here.
        window.titlebarAppearsTransparent = true
        // ADR-0011: without this, `window.title`'s non-empty fallback ("Mochi") is drawn as visible
        // text next to the traffic lights, contradicting ADR-0009's "title text is never rendered".
        // The title itself stays set — Mission Control/Cmd-Tab read it (`AddressBarController`).
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // Below this width the items that never collapse (the segmented control and the address
        // field at its own minimum) stop fitting. Height is deliberately left unconstrained: this
        // change bounds width only.
        window.contentMinSize = NSSize(width: DesignTokens.Layout.normalModeWindowMinWidth, height: 0)
        window.contentView = rootView

        let handle = AppKitWidgetWindowHandle(
            window: window, webView: webView, controls: controls,
            emptyPageHostingView: emptyPageHostingView, progressBar: progressBar
        )

        let toolbar = NSToolbar(identifier: "MochiNormalModeToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.delegate = handle
        window.toolbar = toolbar

        return handle
    }

    /// Builds the Normal Mode toolbar's controls (ADR-0009/ADR-0011) — a standard `NSSearchField`
    /// for the Smart Address Field (no hand-drawn glass wrapper; its native rendering already looks
    /// "more solid" than the surrounding row, per design-language.md) with the refresh affordance
    /// embedded at its trailing edge and a native segmented control for back/forward — all
    /// hosted as `NSToolbarItem` views by `AppKitWidgetWindowHandle`'s `NSToolbarDelegate`
    /// conformance. Settings is not here: it is a stock image+action item built in that delegate.
    private func makeToolbarControls() -> ToolbarControls {
        let addressField = AddressField()
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.placeholderString = "输入网址"
        addressField.lineBreakMode = .byTruncatingTail
        // Bounded elastic width (ADR-0011), replacing the earlier "fill every point left over
        // between the neighbouring items": low hugging still lets `NSToolbarItem` grow the field
        // into spare width — per the `NSToolbarItem.minSize`/`maxSize` SDK header, the toolbar
        // "automatically measure[s] the size of the view using constraints" rather than consulting
        // those (deprecated) properties — but the required upper bound stops that growth at
        // `addressFieldMaxWidth`. Both bounds are required, so the layout system's fitting-size
        // measurement stays inside them; the trap #23 fell into was a huge *low-priority*
        // `width == 10_000` constraint with no upper bound, which became the fitting size itself,
        // so the toolbar decided the item could never fit and swept it straight into the overflow
        // menu instead of sizing it down to the required minimum.
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            addressField.widthAnchor.constraint(
                greaterThanOrEqualToConstant: DesignTokens.Layout.addressFieldMinWidth),
            addressField.widthAnchor.constraint(
                lessThanOrEqualToConstant: DesignTokens.Layout.addressFieldMaxWidth),
            addressField.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.addressFieldHeight),
        ])
        // The field's content is a title/URL the presenter computes, not a free-text search query
        // — the stock clear ("×") button would let AppKit blank `stringValue` directly, bypassing
        // `AddressFieldPresenter` entirely.
        (addressField.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        // The Empty Page (#16) hasn't navigated yet, so the field stays a plain, freely-editable
        // URL box until `hasNavigatedAtLeastOnce` flips — see `AppKitWidgetWindowHandle.loadURL`.
        addressField.isEditable = true

        // Refresh lives inside the field now (ADR-0011) rather than as a standalone
        // `NSToolbarItem`: a plain subview pinned to the trailing edge, with `AddressFieldCell`
        // shrinking the text area by the matching amount. Visibility (hidden until the first real
        // navigation) is owned by `updateEmbeddedRefreshIconVisibility`.
        let addressFieldRefreshButton = toolbarButton(
            icon: .refresh, accessibilityDescription: "刷新",
            diameter: DesignTokens.Layout.addressFieldEmbeddedIconDiameter)
        addressField.addSubview(addressFieldRefreshButton)
        NSLayoutConstraint.activate([
            addressFieldRefreshButton.trailingAnchor.constraint(
                equalTo: addressField.trailingAnchor,
                constant: -DesignTokens.Layout.addressFieldEmbeddedIconTrailingPadding),
            addressFieldRefreshButton.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
        ])

        return ToolbarControls(
            navigationControl: makeNavigationControl(),
            addressField: addressField,
            addressFieldRefreshButton: addressFieldRefreshButton
        )
    }

    /// Back and forward as one joined native `NSSegmentedControl` (ADR-0011) instead of two
    /// independent buttons, matching Safari's own control — still carrying Mochi's hand-drawn
    /// `DesignIcon` glyphs, since a segmented control takes arbitrary `NSImage`s and nothing here
    /// has to fall back to SF Symbols. `.momentary` tracking keeps both segments push-button-like:
    /// neither stays visually "selected" after a click, since these aren't a mutually-exclusive
    /// choice.
    private func makeNavigationControl() -> NSSegmentedControl {
        let control = NSSegmentedControl(
            images: [
                ToolbarStyle.templateImage(for: .chevronLeft, accessibilityDescription: "后退"),
                ToolbarStyle.templateImage(for: .chevronRight, accessibilityDescription: "前进"),
            ],
            trackingMode: .momentary,
            target: nil,
            action: nil
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.segmentStyle = .automatic
        for segment in 0..<control.segmentCount {
            control.setWidth(DesignTokens.Layout.normalModeToolbarButtonDiameter, forSegment: segment)
            control.setImageScaling(.scaleProportionallyDown, forSegment: segment)
        }
        control.setToolTip("后退", forSegment: NavigationSegment.back)
        control.setToolTip("前进", forSegment: NavigationSegment.forward)
        control.heightAnchor.constraint(
            equalToConstant: DesignTokens.Layout.normalModeToolbarButtonDiameter).isActive = true
        return control
    }

    private func makeLoadingProgressBar() -> LoadingProgressBar {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.alphaValue = 0
        bar.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.loadingProgressBarHeight).isActive = true
        let widthConstraint = bar.widthAnchor.constraint(equalToConstant: 0)
        widthConstraint.isActive = true
        return LoadingProgressBar(view: bar, widthConstraint: widthConstraint)
    }

    private func toolbarButton(icon: DesignIcon, accessibilityDescription: String, diameter: Double) -> NSButton {
        let image = ToolbarStyle.templateImage(for: icon, accessibilityDescription: accessibilityDescription)
        let button = NSButton(image: image, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = ToolbarStyle.iconTint()
        button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
        button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        return button
    }

    public func loadURL(_ url: URL, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.loadURL(url)
    }

    public func showEmptyPageContent(in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.showEmptyPage()
    }

    /// Fronts the window and activates the app. `NSApp.activate` is what makes this work from a
    /// Ghost Mode exit triggered by a global hotkey or the tray, where Mochi is not the active
    /// app — at launch (this method's only other caller) it was already active, which is why the
    /// gap went unnoticed until ADR-0012 made "leaving Ghost Mode takes focus" a requirement.
    public func showWindow(_ window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        NSApp.activate()
        handle.window.makeKeyAndOrderFront(nil)
    }

    public func applyZoom(_ zoom: Double, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.webView.pageZoom = zoom
    }

    public func captureWindowState(of window: WidgetWindowHandle) -> WindowState {
        guard let handle = handle(for: window) else {
            return WindowState(frame: WindowFrame(x: 0, y: 0, width: 0, height: 0), zoom: 1.0)
        }
        return WindowState(frame: WindowFrame(cgRect: handle.window.frame), zoom: handle.webView.pageZoom)
    }

    public func onWindowWillClose(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setWillCloseHandler(handler)
    }

    public func visibleScreens() -> [CGRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    public func setToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setToolbarVisible(visible)
    }

    public func reloadPage(in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.reload()
    }

    public func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setURLSubmittedHandler(handler)
    }

    public func setPinned(_ pinned: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setPinned(pinned)
    }

    public func onSettingsRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setSettingsRequestedHandler(handler)
    }

    public func injectScript(_ source: String, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.injectScript(source)
    }

    public func onNavigationFinished(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setNavigationFinishedHandler(handler)
    }

    public func onPageTitleChanged(_ window: WidgetWindowHandle, perform handler: @escaping (String?) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setPageTitleChangedHandler(handler)
    }

    public func onLoadingStateChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setLoadingStateChangedHandler(handler)
    }

    public func onLoadingProgressChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Double) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setLoadingProgressChangedHandler(handler)
    }

    public func setWindowTitle(_ title: String, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setWindowTitle(title)
    }

    public func setNativeChromeVisible(_ visible: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setNativeChromeVisible(visible)
    }

    public func setContentOpacity(_ opacity: Double, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setContentOpacity(opacity)
    }

    public func setMousePassthrough(_ enabled: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setMousePassthrough(enabled)
    }

    public func onMouseEntered(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setMouseEnteredHandler(handler)
    }

    @discardableResult
    public func registerGlobalHotkey(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool {
        GlobalHotkeyRegistry.shared.register(hotkey, perform: handler)
    }

    public func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    public func setSnapThreshold(_ threshold: Double, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setSnapThreshold(threshold)
    }

    /// The tray icon glyph is `DesignIcon.ghost` — Mochi's existing hand-drawn mascot vector —
    /// as a stand-in until docs/design-language.md's dedicated "flattened app icon with a
    /// negative-space window cutout" tray asset is produced by a separate design pass; this
    /// already satisfies the packaging requirement (monochrome, real alpha transparency,
    /// template image) via the same `ToolbarStyle.templateImage` renderer the toolbar buttons use.
    public func createTrayIcon(items: [TrayMenuItem]) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = ToolbarStyle.templateImage(for: .ghost, accessibilityDescription: "Mochi")

        let menu = NSMenu()
        var targets: [TrayMenuItemTarget] = []
        for item in items {
            let target = TrayMenuItemTarget(action: item.action)
            targets.append(target)
            let menuItem = NSMenuItem(title: item.title, action: #selector(TrayMenuItemTarget.invoke), keyEquivalent: "")
            menuItem.target = target
            menu.addItem(menuItem)
        }
        statusItem.menu = menu

        tray = (statusItem, targets)
    }

    public func terminateApp() {
        NSApplication.shared.terminate(nil)
    }

    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// `CGEventPostToPid` targeted at this process's own PID (ADR-0003) — the widget's page has
    /// no keyboard focus while the user is working in another app, so the event is delivered
    /// directly to this process rather than relying on window key-status/first-responder.
    public func forwardKeystroke(_ keystroke: Hotkey) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let flags = Self.cgEventFlags(fromCarbonModifiers: keystroke.modifierFlags)
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keystroke.keyCode), keyDown: true) {
            keyDown.flags = flags
            keyDown.postToPid(pid)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keystroke.keyCode), keyDown: false) {
            keyUp.flags = flags
            keyUp.postToPid(pid)
        }
    }

    /// `Hotkey.modifierFlags` is expressed in Carbon's bit values everywhere else in the codebase
    /// (`GlobalHotkeyRegistry`'s `RegisterEventHotKey`) — translated here since `CGEvent` needs
    /// its own, differently-valued `CGEventFlags` bitmask instead.
    private static func cgEventFlags(fromCarbonModifiers carbonFlags: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if carbonFlags & 0x0100 != 0 { flags.insert(.maskCommand) }
        if carbonFlags & 0x0200 != 0 { flags.insert(.maskShift) }
        if carbonFlags & 0x0800 != 0 { flags.insert(.maskAlternate) }
        if carbonFlags & 0x1000 != 0 { flags.insert(.maskControl) }
        return flags
    }

    private func handle(for window: WidgetWindowHandle) -> AppKitWidgetWindowHandle? {
        window as? AppKitWidgetWindowHandle
    }
}
