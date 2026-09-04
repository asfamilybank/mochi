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

    static func mutedIconTint() -> NSColor {
        dynamicColor(light: DesignTokens.glassPalette(dark: false).iconMuted, dark: DesignTokens.glassPalette(dark: true).iconMuted)
    }

    static func glassTint() -> NSColor {
        dynamicColor(light: DesignTokens.glassPalette(dark: false).glassFill, dark: DesignTokens.glassPalette(dark: true).glassFill)
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

/// A search field that reports the moment it's clicked, *before* AppKit's own `mouseDown`
/// processing runs — needed so the Smart Address Field (#18) can flip into its editable state
/// (`AddressFieldPresenter`) in time for that same click to place a cursor, rather than the user
/// needing a second click after the field becomes editable.
private final class AddressField: NSSearchField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
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
    let backButton: NSButton
    let forwardButton: NSButton
    let refreshButton: NSButton
    let pinButton: NSButton
    let addressField: AddressField
    let settingsButton: NSButton
}

/// Ghost Mode's summoned toolbar overlay's (#10) controls — a deliberately separate set of
/// button instances from `ToolbarControls`, per the ticket's design decision that the overlay
/// must not reuse the Normal Mode toolbar's component, even though both wire the same
/// `togglePinned`/`reload` actions on `AppKitWidgetWindowHandle`. Order matches
/// `DesignTokens.ghostModeSummonedToolbarOrder`. Unaffected by ADR-0009 — still its own floating
/// `NSGlassEffectView` capsule, independent of the Normal Mode toolbar's native chrome.
fileprivate struct SummonedToolbarControls {
    let pinButton: NSButton
    let ghostModeToggleButton: NSButton
    let refreshButton: NSButton
}

/// The Loading Progress Bar (#18): a thin line docked to the content area's top edge, overlaid
/// on top of `webView`/the Empty Page rather than reserving its own layout row — matching
/// design-language.md's "不加载时不占用界面空间". `widthConstraint`'s `constant` is driven
/// straight from `WKWebView.estimatedProgress`.
fileprivate struct LoadingProgressBar {
    let view: NSView
    let widthConstraint: NSLayoutConstraint
}

/// Normal Mode's window chrome (ADR-0009): a native `NSToolbar` in `.unifiedCompact` style —
/// traffic lights, back/forward/refresh, the Smart Address Field, Pin, and settings all on one
/// row, rendered with the system's own Liquid Glass material — sitting above the WKWebView.
///
/// Colors, corner radii, spacing, and the bespoke vector icon set all come from `DesignTokens`/
/// `DesignIcon` (#17) — nothing here writes its own numbers.
final class AppKitWidgetWindowHandle: NSObject, WidgetWindowHandle, NSWindowDelegate, NSSearchFieldDelegate, WKNavigationDelegate {
    private static let backItemID = NSToolbarItem.Identifier("com.mochi.toolbar.back")
    private static let forwardItemID = NSToolbarItem.Identifier("com.mochi.toolbar.forward")
    private static let refreshItemID = NSToolbarItem.Identifier("com.mochi.toolbar.refresh")
    private static let addressItemID = NSToolbarItem.Identifier("com.mochi.toolbar.address")
    private static let pinItemID = NSToolbarItem.Identifier("com.mochi.toolbar.pin")
    private static let settingsItemID = NSToolbarItem.Identifier("com.mochi.toolbar.settings")
    /// The Normal Mode toolbar's fixed button order (`DesignTokens.normalModeToolbarOrder`, minus
    /// the not-yet-implemented Ghost Mode toggle button — see AppKitPlatformOps's doc comment).
    private static let toolbarItemOrder: [NSToolbarItem.Identifier] = [
        backItemID, forwardItemID, refreshItemID, addressItemID, pinItemID, settingsItemID,
    ]

    let window: NSWindow
    let webView: WKWebView
    private let controls: ToolbarControls
    private let summonedToolbarContainer: NSView
    private let summonedControls: SummonedToolbarControls
    private let progressBar: LoadingProgressBar
    /// The Empty Page's (#16) native content, occupying the same slot as `webView` inside
    /// `contentContainer` — exactly one of the two is visible at a time, toggled by `loadURL`/
    /// `showEmptyPage` rather than swapped in and out of the view hierarchy.
    private let emptyPageHostingView: NSHostingView<EmptyPageView>
    private let addressFieldHoverTracker = HoverTracker()
    private var willCloseHandler: (() -> Void)?
    private var urlSubmittedHandler: ((URL) -> Void)?
    private var pinnedChangedHandler: ((Bool) -> Void)?
    private var settingsRequestedHandler: (() -> Void)?
    private var navigationFinishedHandler: (() -> Void)?
    private var mouseEnteredHandler: (() -> Void)?
    private var summonedGhostModeToggleHandler: (() -> Void)?
    private var pageTitleChangedHandler: ((String?) -> Void)?
    private var loadingStateChangedHandler: ((Bool) -> Void)?
    private var loadingProgressChangedHandler: ((Double) -> Void)?
    private var isPinned = false
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
        window: NSWindow, webView: WKWebView, controls: ToolbarControls,
        summonedToolbarContainer: NSView, summonedControls: SummonedToolbarControls,
        emptyPageHostingView: NSHostingView<EmptyPageView>, progressBar: LoadingProgressBar
    ) {
        self.window = window
        self.webView = webView
        self.controls = controls
        self.summonedToolbarContainer = summonedToolbarContainer
        self.summonedControls = summonedControls
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
        controls.backButton.target = self
        controls.backButton.action = #selector(goBack)
        controls.forwardButton.target = self
        controls.forwardButton.action = #selector(goForward)
        controls.refreshButton.target = self
        controls.refreshButton.action = #selector(reload)
        controls.pinButton.target = self
        controls.pinButton.action = #selector(togglePinned)
        controls.pinButton.wantsLayer = true
        controls.pinButton.layer?.cornerRadius = DesignTokens.Layout.normalModeToolbarButtonDiameter / 2
        controls.settingsButton.target = self
        controls.settingsButton.action = #selector(handleSettingsRequested)
        summonedControls.refreshButton.target = self
        summonedControls.refreshButton.action = #selector(reload)
        summonedControls.pinButton.target = self
        summonedControls.pinButton.action = #selector(togglePinned)
        summonedControls.pinButton.wantsLayer = true
        summonedControls.pinButton.layer?.cornerRadius = DesignTokens.Layout.toolbarButtonDiameter / 2
        summonedControls.ghostModeToggleButton.target = self
        summonedControls.ghostModeToggleButton.action = #selector(handleSummonedGhostModeToggle)
        summonedControls.ghostModeToggleButton.wantsLayer = true
        summonedControls.ghostModeToggleButton.layer?.cornerRadius = DesignTokens.Layout.toolbarButtonDiameter / 2
        observeNavigationState()
        updatePinButtonAppearance()
        updateSummonedGhostModeToggleAppearance()
        updateProgressBarColor()
        // The Pin capsule's tint (and the progress bar's fill) are baked into CALayer colors (not
        // dynamic NSColors), so unlike everywhere else in this file they need to be re-applied
        // whenever the system accent color or the window's light/dark appearance changes, instead
        // of re-resolving for free at draw time.
        appearanceObservation = window.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.updatePinButtonAppearance()
            self?.updateSummonedGhostModeToggleAppearance()
            self?.updateProgressBarColor()
        }
        accentColorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updatePinButtonAppearance()
            self?.updateSummonedGhostModeToggleAppearance()
            self?.updateProgressBarColor()
        }
    }

    deinit {
        if let accentColorObserver {
            NotificationCenter.default.removeObserver(accentColorObserver)
        }
    }

    private func observeNavigationState() {
        setNavigationButton(controls.backButton, enabled: webView.canGoBack)
        setNavigationButton(controls.forwardButton, enabled: webView.canGoForward)
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.setNavigationButton(self.controls.backButton, enabled: change.newValue ?? false)
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                self.setNavigationButton(self.controls.forwardButton, enabled: change.newValue ?? false)
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

    private func setNavigationButton(_ button: NSButton, enabled: Bool) {
        button.isEnabled = enabled
        button.contentTintColor = enabled ? ToolbarStyle.iconTint() : ToolbarStyle.mutedIconTint()
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    /// Not `private` — shared as the target-action for both the Normal Mode toolbar's refresh
    /// button and the summoned overlay's own refresh button (#10), and called directly by
    /// `AppKitPlatformOps.reloadPage(in:)` for the default 刷新页面 hotkey (#12).
    @objc func reload() {
        webView.reload()
    }

    @objc private func togglePinned() {
        applyPinned(!isPinned)
        pinnedChangedHandler?(isPinned)
    }

    /// Applies a pinned state to the window without notifying `pinnedChangedHandler` — used to
    /// restore a persisted state on launch, where there is nothing new to persist back.
    func setPinned(_ pinned: Bool) {
        applyPinned(pinned)
    }

    private func applyPinned(_ pinned: Bool) {
        isPinned = pinned
        window.level = isPinned ? .floating : .normal
        updatePinButtonAppearance()
    }

    /// The Pin toggle's active state: a tinted glass background + border + icon in the
    /// system accent color, matching macOS's own selected-state glass tinting (design-language.md,
    /// "工具栏与工具栏"). Inactive state falls back to the plain toolbar icon tint.
    private func updatePinButtonAppearance() {
        applyPinAppearance(to: controls.pinButton)
        applyPinAppearance(to: summonedControls.pinButton)
    }

    private func applyPinAppearance(to button: NSButton) {
        guard let layer = button.layer else { return }
        if isPinned {
            let tint = DesignTokens.accentTint(DesignTokens.resolveSystemAccent())
            layer.backgroundColor = NSColor(rgba: tint.background).cgColor
            layer.borderWidth = 1
            layer.borderColor = NSColor(rgba: tint.border).cgColor
            button.contentTintColor = NSColor(rgba: tint.icon)
        } else {
            layer.backgroundColor = nil
            layer.borderWidth = 0
            button.contentTintColor = ToolbarStyle.iconTint()
        }
    }

    /// The summoned overlay's Ghost Mode toggle button (#10) always renders in the same tinted
    /// "active" style Pin uses when on — the overlay only ever appears while Ghost Mode already
    /// is active (`GhostModeController.toggleSummonedToolbar`'s guard), so there is no "off" state
    /// for this particular button to represent while it's visible at all.
    private func updateSummonedGhostModeToggleAppearance() {
        guard let layer = summonedControls.ghostModeToggleButton.layer else { return }
        let tint = DesignTokens.accentTint(DesignTokens.resolveSystemAccent())
        layer.backgroundColor = NSColor(rgba: tint.background).cgColor
        layer.borderWidth = 1
        layer.borderColor = NSColor(rgba: tint.border).cgColor
        summonedControls.ghostModeToggleButton.contentTintColor = NSColor(rgba: tint.icon)
    }

    /// The Loading Progress Bar's fill color, system accent — baked into a `CALayer` (see the
    /// class-level comment), so re-applied on every accent/appearance change alongside Pin.
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

    func setPinnedChangedHandler(_ handler: @escaping (Bool) -> Void) {
        pinnedChangedHandler = handler
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

    func setSummonedToolbarVisible(_ visible: Bool) {
        summonedToolbarContainer.isHidden = !visible
    }

    func setSummonedGhostModeToggleHandler(_ handler: @escaping () -> Void) {
        summonedGhostModeToggleHandler = handler
    }

    @objc private func handleSummonedGhostModeToggle() {
        summonedGhostModeToggleHandler?()
    }

    func setFrame(_ frame: WindowFrame) {
        window.setFrame(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), display: true)
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

    func setWindowHidden(_ hidden: Bool) {
        if hidden {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
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
        switch itemIdentifier {
        case Self.backItemID:
            item.view = controls.backButton
        case Self.forwardItemID:
            item.view = controls.forwardButton
        case Self.refreshItemID:
            item.view = controls.refreshButton
        case Self.addressItemID:
            item.view = controls.addressField
        case Self.pinItemID:
            item.view = controls.pinButton
        case Self.settingsItemID:
            item.view = controls.settingsButton
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
        let (summonedToolbarContainer, summonedControls) = makeSummonedToolbarOverlay()

        // The progress bar overlays the top edge of the content area (added after it, so it
        // draws on top) instead of occupying its own row — it takes no layout space while hidden.
        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(contentContainer)
        rootView.addSubview(progressBar.view)
        // A plain `addSubview`, not part of any stack's managed layout — this floats above
        // `webView` in z-order without joining layout, which is what lets it appear/disappear
        // without resizing or reflowing the window's content (#10's AC).
        rootView.addSubview(summonedToolbarContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            progressBar.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            progressBar.view.topAnchor.constraint(equalTo: rootView.topAnchor),
            summonedToolbarContainer.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            summonedToolbarContainer.topAnchor.constraint(
                equalTo: rootView.topAnchor, constant: DesignTokens.Layout.ghostModeSummonedToolbarTopMargin),
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
        window.toolbarStyle = .unifiedCompact
        window.contentView = rootView

        let handle = AppKitWidgetWindowHandle(
            window: window, webView: webView, controls: controls,
            summonedToolbarContainer: summonedToolbarContainer, summonedControls: summonedControls,
            emptyPageHostingView: emptyPageHostingView, progressBar: progressBar
        )

        let toolbar = NSToolbar(identifier: "MochiNormalModeToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.delegate = handle
        window.toolbar = toolbar

        return handle
    }

    /// Ghost Mode's summoned toolbar overlay (#10): a small floating glass capsule holding only
    /// Pin, Ghost Mode toggle, and Refresh (`DesignTokens.ghostModeSummonedToolbarOrder`) — its
    /// own dedicated view built from fresh button instances, independent of the Normal Mode
    /// toolbar's (per the ticket's design decision), matching
    /// `design/mochi/GhostToolbar.dc.html`'s layout. Starts hidden. Unaffected by ADR-0009.
    private func makeSummonedToolbarOverlay() -> (container: NSView, controls: SummonedToolbarControls) {
        let pinButton = toolbarButton(icon: .pin, accessibilityDescription: "置顶", diameter: DesignTokens.Layout.toolbarButtonDiameter)
        let ghostModeToggleButton = toolbarButton(
            icon: .ghost, accessibilityDescription: "退出 Ghost Mode", diameter: DesignTokens.Layout.toolbarButtonDiameter)
        let refreshButton = toolbarButton(icon: .refresh, accessibilityDescription: "刷新", diameter: DesignTokens.Layout.toolbarButtonDiameter)

        let buttonsStack = NSStackView(views: [pinButton, ghostModeToggleButton, refreshButton])
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = DesignTokens.Layout.toolbarButtonSpacing
        buttonsStack.edgeInsets = NSEdgeInsets(
            top: DesignTokens.Layout.toolbarInnerPaddingVertical,
            left: DesignTokens.Layout.toolbarInnerPaddingHorizontal,
            bottom: DesignTokens.Layout.toolbarInnerPaddingVertical,
            right: DesignTokens.Layout.toolbarInnerPaddingHorizontal
        )

        let glass = NSGlassEffectView()
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerRadius = DesignTokens.Layout.toolbarCapsuleCornerRadius
        glass.tintColor = ToolbarStyle.glassTint()
        glass.contentView = buttonsStack
        glass.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.toolbarCapsuleHeight).isActive = true
        glass.isHidden = true

        return (
            glass,
            SummonedToolbarControls(pinButton: pinButton, ghostModeToggleButton: ghostModeToggleButton, refreshButton: refreshButton)
        )
    }

    /// Builds the Normal Mode toolbar's controls (ADR-0009) — a standard `NSSearchField` for the
    /// Smart Address Field (no hand-drawn glass wrapper; its native rendering already looks
    /// "more solid" than the surrounding row, per design-language.md) and bespoke-icon
    /// `NSButton`s for the rest, all hosted as `NSToolbarItem` views by
    /// `AppKitWidgetWindowHandle`'s `NSToolbarDelegate` conformance.
    private func makeToolbarControls() -> ToolbarControls {
        let addressField = AddressField()
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.placeholderString = "输入网址"
        addressField.lineBreakMode = .byTruncatingTail
        // Low hugging priority (with no opposing upper-bound constraint) is what makes
        // `NSToolbarItem` grow this field to fill the toolbar's spare width — per the
        // `NSToolbarItem.minSize`/`maxSize` SDK header, the toolbar "automatically measure[s] the
        // size of the view using constraints" rather than consulting those (deprecated) properties.
        // An earlier attempt encoded "expand to fill" as its own `width == 10_000` constraint at
        // `.defaultLow`, but with nothing else constraining the width from above, that constraint
        // *was* the value the layout system's fitting-size measurement settled on — so the toolbar
        // saw an item that wanted ~10,000pt, decided it could never fit, and swept it into the
        // overflow menu outright instead of sizing it down to the required minimum (#23).
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        addressField.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.addressFieldHeight).isActive = true
        // The field's content is a title/URL the presenter computes, not a free-text search query
        // — the stock clear ("×") button would let AppKit blank `stringValue` directly, bypassing
        // `AddressFieldPresenter` entirely.
        (addressField.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        // The Empty Page (#16) hasn't navigated yet, so the field stays a plain, freely-editable
        // URL box until `hasNavigatedAtLeastOnce` flips — see `AppKitWidgetWindowHandle.loadURL`.
        addressField.isEditable = true

        return ToolbarControls(
            backButton: toolbarButton(
                icon: .chevronLeft, accessibilityDescription: "后退", diameter: DesignTokens.Layout.normalModeToolbarButtonDiameter),
            forwardButton: toolbarButton(
                icon: .chevronRight, accessibilityDescription: "前进", diameter: DesignTokens.Layout.normalModeToolbarButtonDiameter),
            refreshButton: toolbarButton(
                icon: .refresh, accessibilityDescription: "刷新", diameter: DesignTokens.Layout.normalModeToolbarButtonDiameter),
            pinButton: toolbarButton(
                icon: .pin, accessibilityDescription: "置顶", diameter: DesignTokens.Layout.normalModeToolbarButtonDiameter),
            addressField: addressField,
            // docs/design-language.md's toolbar button list documents the settings entry as the
            // "更多" (⋯) affordance, not a dedicated glyph — reusing `.moreHorizontal` here rather
            // than introducing a new icon.
            settingsButton: toolbarButton(
                icon: .moreHorizontal, accessibilityDescription: "设置", diameter: DesignTokens.Layout.normalModeToolbarButtonDiameter)
        )
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

    public func showWindow(_ window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
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

    public func setSummonedToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setSummonedToolbarVisible(visible)
    }

    public func onSummonedToolbarGhostModeToggleRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setSummonedGhostModeToggleHandler(handler)
    }

    public func reloadPage(in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.reload()
    }

    public func setWindowFrame(_ frame: WindowFrame, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setFrame(frame)
    }

    public func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setURLSubmittedHandler(handler)
    }

    public func setPinned(_ pinned: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setPinned(pinned)
    }

    public func onPinnedChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setPinnedChangedHandler(handler)
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

    public func setWindowHidden(_ hidden: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setWindowHidden(hidden)
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
