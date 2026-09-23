import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import WebKit

/// Bridges the framework-agnostic value types — `DesignTokens` and the two bespoke glyphs,
/// `GhostGlyph` and `MochiGlyph` — into the AppKit types the UI draws with, and resolves
/// `DesignTokens.Symbol` names into system symbol images.
/// Kept separate from `DesignTokens.swift` itself so that module stays free of AppKit-specific
/// rendering concerns beyond accent-color resolution.
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

    /// A real SF Symbol, which every glyph but the ghost now is. Omitting `pointSize` leaves
    /// AppKit's own default configuration in place — what `NSToolbarItem` and
    /// `NSSegmentedControl` expect, since they size their own content; the address field's
    /// embedded refresh icon and the tray glyph pin a size explicitly because they sit in boxes
    /// AppKit doesn't measure for us.
    static func symbolImage(_ name: String, accessibilityDescription: String, pointSize: Double? = nil) -> NSImage {
        // A missing symbol means a mistyped name, not a runtime condition worth degrading for:
        // every name passed here exists in this deployment target's SDK (verified by
        // `DesignTokensTests.everySymbolNameResolvesAgainstTheSDK`).
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else {
            preconditionFailure("SF Symbol \"\(name)\" is not in this SDK")
        }
        guard let pointSize else { return image }
        return image.withSymbolConfiguration(
            .init(pointSize: pointSize, weight: .regular, scale: .medium)) ?? image
    }

    /// Renders one of Mochi's bespoke glyphs to the metric contract the SF Symbols beside it
    /// satisfy (`SymbolMetrics`): a canvas sized off the point size, a cap-height
    /// `alignmentRect` so it sits on the text baseline, and a stroke weight that tracks point
    /// size. The ink box is fitted into the canvas here; `draw` paints on the 24×24 design grid
    /// and is handed the scale it was fitted by, because a stroke has to divide that back out to
    /// land on `metrics.strokeWidth` in final points.
    static func glyphImage(
        pointSize: Double,
        accessibilityDescription: String,
        ink: CGRect,
        draw: @escaping (_ metrics: SymbolMetrics, _ scale: CGFloat) -> Void
    ) -> NSImage {
        let metrics = SymbolMetrics.forGlyph(
            pointSize: pointSize,
            capHeight: Double(NSFont.systemFont(ofSize: pointSize).capHeight),
            inkAspectRatio: Double(ink.width / ink.height))

        let image = NSImage(size: metrics.canvasSize, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = CGFloat(metrics.fitScale(forInk: ink))
            context.translateBy(x: (metrics.canvasSize.width - ink.width * scale) / 2,
                                y: (metrics.canvasSize.height - ink.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -ink.minX, y: -ink.minY)

            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw(metrics, scale)
            return true
        }
        image.isTemplate = true
        image.alignmentRect = metrics.alignmentRect
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// The ghost mascot — SF Symbols has no ghost, so the Ghost Mode toolbar item keeps a
    /// bespoke one. Silhouette stroked, eyes filled: see `GhostGlyph` on why those are two paths.
    static func ghostImage(pointSize: Double, accessibilityDescription: String) -> NSImage {
        // The ink's stroke term uses the grid-space reference weight rather than the final one
        // (which isn't known until the fit scale is solved, and that needs the ink box) — the
        // resulting sub-0.1pt difference in ink extent is absorbed by `SymbolMetrics.inkInset`.
        glyphImage(pointSize: pointSize,
                   accessibilityDescription: accessibilityDescription,
                   ink: GhostGlyph.inkBounds(strokeWidth: DesignTokens.Layout.iconStrokeWidth)) { metrics, scale in
            let outline = NSBezierPath(cgPath: GhostGlyph.outlinePath)
            // Stroking happens inside the scaled context, so divide out `scale` to land on
            // `metrics.strokeWidth` in final points.
            outline.lineWidth = metrics.strokeWidth / scale
            outline.lineCapStyle = .round
            outline.lineJoinStyle = .round
            outline.stroke()
            NSBezierPath(cgPath: GhostGlyph.eyesPath).fill()
        }
    }

    /// Mochi's brand mark, worn by the menu-bar tray (ADR-0015). One filled path under the
    /// even-odd rule so the window comes out as a hole rather than a second shape — a template
    /// image has to stay pure monochrome for AppKit to re-tint it against light and dark menu
    /// bars. Nothing is stroked, so neither closure parameter is needed.
    static func mochiImage(pointSize: Double, accessibilityDescription: String) -> NSImage {
        glyphImage(pointSize: pointSize,
                   accessibilityDescription: accessibilityDescription,
                   ink: MochiGlyph.inkBounds) { _, _ in
            let body = NSBezierPath(cgPath: MochiGlyph.path)
            body.windingRule = .evenOdd
            body.fill()
        }
    }

    /// Point sizes the glyphs are pinned to where AppKit isn't sizing them for us.
    enum GlyphSize {
        /// Inside the address field's 20pt embedded-icon box.
        static let addressFieldEmbedded: Double = 13
        /// The address field's leading site icon, when a symbol stands in for a missing favicon.
        /// Smaller than the 16pt box it sits in, the way a favicon's own artwork has its margins.
        static let addressFieldLeading: Double = 13
        /// The tray glyph. `NSStatusBar.system.thickness` is 22pt, and a 15pt symbol's canvas is
        /// 18pt tall — the size Apple's own menu-bar glyphs occupy.
        static let tray: Double = 15
        /// A stock `NSToolbarItem`'s glyph, so the hand-drawn ghost matches the SF Symbols in
        /// the neighbouring items, which AppKit renders at its own default configuration.
        static let toolbarItem: Double = 13
    }
}

private extension NSColor {
    convenience init(rgba: DesignTokens.RGBA) {
        self.init(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }
}

/// Bridges the injected scroll-position script back into AppKit. A separate object because
/// `WKUserContentController` retains its message handlers, and having the window handle be its own
/// handler would make that a retain cycle.
private final class PageScrollReporter: NSObject, WKScriptMessageHandler {
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let atTop = message.body as? Bool else { return }
        onChange(atTop)
    }
}

/// Reserves room at both ends of the address field's text area — the leading site icon and the
/// trailing refresh affordance (ADR-0011) — so a long title/URL truncates before it reaches either
/// instead of sliding underneath. `NSTextField` exposes no view-level hook for that geometry; the
/// cell owns it, which is why this is a cell subclass rather than a layout tweak on the field.
private final class AddressFieldCell: NSTextFieldCell {
    /// Points shaved off the leading edge, for the site icon / globe / magnifying glass.
    var leadingInset: CGFloat = 0
    /// Points shaved off the trailing edge; `0` while the refresh icon is hidden.
    var trailingInset: CGFloat = 0

    /// Both the drawn text and the field editor derive from this, so insetting here keeps the
    /// caret and the selection inside the same box the static text occupies.
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.drawingRect(forBounds: rect)
        textRect.origin.x += leadingInset
        textRect.size.width = max(0, textRect.width - leadingInset - trailingInset)
        return textRect
    }
}

/// The Smart Address Field (#18).
///
/// An `NSTextField` with `.roundedBezel`, not the `NSSearchField` this started as. Two reasons,
/// both measured against the real control:
///
/// 1. **Focus ring.** `NSSearchField` draws its ring *on top of* its own border rather than
///    outside it, so the two overlap and any clipping at the edges turns the ring's end caps into
///    flat vertical lines. `NSTextField` draws the ring outside the border with a gap between
///    them — the separation every other focused field on the system has, and what Safari's own
///    address bar (`AXTextField` with no `AXSearchField` subrole — it is not a search field
///    either) looks like.
/// 2. **No stock buttons to fight.** The search field's cancel and search button cells are
///    rebuilt by AppKit on every toolbar layout pass, so keeping a custom leading glyph on one
///    and a cleared cancel button on the other meant re-applying both from `layout()` forever —
///    and assigning to either property is itself what provoked the rebuild. A plain text field
///    has neither, so the leading icon is just a subview nobody else touches.
private final class AddressField: NSTextField {
    var onMouseDown: (() -> Void)?

    /// `NSControl` builds its cell from this at `init(frame:)` time — the only way to get
    /// `AddressFieldCell`'s text-rect insets in without swapping a live `cell` out from under
    /// the field.
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
    /// What the address toolbar item actually hosts: `addressField` inset by
    /// `DesignTokens.Layout.addressFieldFocusRingInset` on every side, so its focus ring isn't
    /// clipped. Built once here rather than in `itemForItemIdentifier`, which AppKit may call
    /// again for the same identifier — a fresh container per call would re-parent the field and
    /// pile up duplicate constraints.
    let addressFieldContainer: NSView
    /// The site icon at `addressField`'s leading edge — a plain subview now that the field is an
    /// `NSTextField`, rather than an image pushed onto `NSSearchFieldCell`'s stock search button
    /// (which AppKit rebuilt on every layout pass).
    let addressFieldLeadingIconView: NSImageView
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
/// Colors, corner radii, spacing, symbol names, and the one bespoke glyph all come from
/// `DesignTokens`/`GhostGlyph` (#17) — nothing here writes its own numbers.
final class AppKitWidgetWindowHandle: NSObject, WidgetWindowHandle, NSWindowDelegate, NSTextFieldDelegate, WKNavigationDelegate {
    private static let navigationItemID = NSToolbarItem.Identifier("com.mochi.toolbar.navigation")
    private static let addressItemID = NSToolbarItem.Identifier("com.mochi.toolbar.address")
    private static let ghostModeItemID = NSToolbarItem.Identifier("com.mochi.toolbar.ghostMode")
    private static let settingsItemID = NSToolbarItem.Identifier("com.mochi.toolbar.settings")
    /// The Normal Mode toolbar's fixed item order (`DesignTokens.normalModeToolbarOrder`).
    /// Three items of our own: back and forward share one segmented control, and refresh is
    /// embedded in the address field rather than being an item of its own (ADR-0011).
    ///
    /// The single `.flexibleSpace` is what makes the address field's bounded width read correctly
    /// (ADR-0011): once the field stops stretching to fill everything left over, the slack has to
    /// go somewhere, and parking all of it between the field and the trailing items keeps them
    /// flush with the window's trailing edge. Without it the whole row packs to the left and
    /// leaves a dead gap after the trailing items. Ghost Mode (#44) sits between that space and
    /// settings — always visible while settings is the one item allowed to collapse.
    private static let toolbarItemOrder: [NSToolbarItem.Identifier] = [
        navigationItemID, addressItemID, .flexibleSpace, ghostModeItemID, settingsItemID,
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
    /// The error page's (#38) native content — same "shared container, `isHidden` toggle"
    /// structure as `emptyPageHostingView`, occupying the same slot.
    private let errorPageHostingView: NSHostingView<ErrorPageView>
    private let addressFieldHoverTracker = HoverTracker()
    private var willCloseHandler: (() -> Void)?
    private var urlSubmittedHandler: ((URL) -> Void)?
    private var settingsRequestedHandler: (() -> Void)?
    private var ghostModeToggleRequestedHandler: (() -> Void)?
    private var navigationFinishedHandler: (() -> Void)?
    private var navigationFailedHandler: ((String) -> Void)?
    private var mouseInsideChangedHandler: ((Bool) -> Void)?
    private var pageTitleChangedHandler: ((String?) -> Void)?
    private var loadingStateChangedHandler: ((Bool) -> Void)?
    private var loadingProgressChangedHandler: ((Double) -> Void)?
    /// Set on `windowWillEnterFullScreen`, cleared on `windowDidExitFullScreen` — `window.frame`
    /// itself is the screen-filling fullscreen frame for the whole time in between, so anything
    /// reading a persistable window geometry (`frameToPersist`) needs this instead. Without it, a
    /// persist that lands mid-fullscreen (e.g. ⌘Q) would save a frame that fills the screen, and
    /// the next launch would start the window that way (#38).
    private var frameBeforeFullscreen: NSRect?
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
    private let contentTopInset: NSLayoutConstraint
    /// The toolbar-row height the web view's obscured inset is currently set to, so a repeated
    /// measurement can be recognised and skipped.
    private var appliedTitlebarHeight: CGFloat
    /// How much `setNativeChromeVisible(false)` took off the window's height — the toolbar row it
    /// no longer has — so leaving Ghost Mode can give back exactly that, and a frame captured in
    /// the meantime can be persisted at its Normal Mode size.
    private var ghostModeHeightReduction: CGFloat = 0
    /// Set for the whole of Ghost Mode, transitions included, so `updateTitlebarMetrics` keeps its
    /// hands off the inset. Removing `.titled` passes through a half-torn-down titlebar, and the
    /// `contentLayoutRect` observation fires in the middle of it — measured: it read 32pt instead
    /// of 52, the inset followed, and the page's viewport grew 20pt and shifted up.
    private var isNativeChromeHidden = false
    /// The content container's top edge pinned to the window's — Normal Mode's sizing.
    private let contentContainerTopConstraint: NSLayoutConstraint
    /// Stands in for `contentContainerTopConstraint` in Ghost Mode: the container keeps the height
    /// it had while the window shrinks around it, so its top (the toolbar strip) hangs off the
    /// window's top edge and is clipped away. The web view, the Empty Page and the error page are
    /// all pinned to the container, so none of them resizes or moves on screen.
    private let contentContainerGhostModeHeight: NSLayoutConstraint
    /// Whether the page is scrolled to its very top. Reported by an injected script — `WKWebView`
    /// has no scroll position to observe from here, and AppKit's own toolbar/scroll coupling only
    /// works for an `NSScrollView` it can find in the content view, which a web view is not.
    private var isPageAtTop = true
    /// Held so Normal Mode can put it back after Ghost Mode — see `setNativeChromeVisible`.
    fileprivate var normalModeToolbar: NSToolbar?
    private let faviconLoader = FaviconLoader()
    /// The current page's favicon, or `nil` while none has been fetched for it. Reset on every
    /// real navigation rather than left to be overwritten — otherwise the previous site's icon
    /// would stay on screen for as long as the new one takes to load, which on a slow site is
    /// long enough to read as "this is that site".
    private var siteIcon: NSImage?
    private let defaultWindowBackgroundColor: NSColor
    private var navigationObservations: [NSKeyValueObservation] = []
    private var appearanceObservation: NSKeyValueObservation?
    /// `contentLayoutRect` is KVO-compliant and changes exactly when the titlebar strip's height
    /// becomes known (and whenever it changes after), which beats guessing at a runloop turn.
    private var contentLayoutObservation: NSKeyValueObservation?
    private var accentColorObserver: NSObjectProtocol?

    fileprivate init(
        window: NSWindow, webView: WKWebView, controls: ToolbarControls,
        emptyPageHostingView: NSHostingView<EmptyPageView>, errorPageHostingView: NSHostingView<ErrorPageView>,
        progressBar: LoadingProgressBar, contentTopInset: NSLayoutConstraint,
        contentContainerTopConstraint: NSLayoutConstraint
    ) {
        self.window = window
        self.webView = webView
        self.controls = controls
        self.emptyPageHostingView = emptyPageHostingView
        self.errorPageHostingView = errorPageHostingView
        self.progressBar = progressBar
        self.contentTopInset = contentTopInset
        self.appliedTitlebarHeight = contentTopInset.constant
        self.contentContainerTopConstraint = contentContainerTopConstraint
        self.contentContainerGhostModeHeight = webView.superview!.heightAnchor.constraint(equalToConstant: 0)
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
        updateAddressFieldIcons()
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
        installPageScrollReporting()
        contentLayoutObservation = window.observe(\.contentLayoutRect, options: [.new]) { [weak self] _, _ in
            self?.updateTitlebarMetrics()
        }
        updateTitlebarMetrics()
        updateTitlebarBackdrop()
    }

    func windowDidResize(_ notification: Notification) {
        updateTitlebarMetrics()
    }

    /// Height of the strip the toolbar occupies, taken from the window rather than hardcoded so it
    /// tracks the toolbar style and whatever the system decides that row should be. Drives both the
    /// backdrop's height and the web view's obscured inset, so the two can never disagree.
    /// `nil` when the window can't answer yet. Before it has laid out, `contentLayoutRect` comes
    /// back empty and the subtraction yields the *entire* window height — which, applied, made the
    /// backdrop cover the whole page instead of the toolbar strip (the page appeared to be a grey
    /// sheet until the first scroll hid the backdrop). A toolbar row can't be half the window, so
    /// anything that large is the un-laid-out case, not a measurement.
    private var titlebarHeight: CGFloat? {
        let layoutHeight = window.contentLayoutRect.height
        let total = window.frame.height
        guard layoutHeight > 0, total > layoutHeight else { return nil }
        let height = total - layoutHeight
        guard height <= total / 2 else { return nil }
        return height
    }

    /// Keeps the backdrop, the web view's layout viewport and the progress bar in step with the
    /// titlebar's real height. `obscuredContentInsets` is what stops the page's own layout from
    /// hiding under the toolbar: the viewport shrinks by this much, fixed and sticky elements
    /// reposition themselves, and none of it changes when the toolbar's background does — so
    /// scrolling never makes the page jump.
    private func updateTitlebarMetrics() {
        guard !isNativeChromeHidden, let height = titlebarHeight else { return }
        // Only when it actually changed. Re-assigning the same `obscuredContentInsets` makes
        // WebKit redo layout without repainting, which left the page blank — a flat grey sheet
        // until the first scroll forced a draw. `contentLayoutRect` fires this more than once
        // while the window settles, so the repeats are the common case, not the rare one.
        guard abs(appliedTitlebarHeight - height) > 0.5 else { return }
        appliedTitlebarHeight = height
        contentTopInset.constant = height
        webView.obscuredContentInsets = NSEdgeInsets(top: height, left: 0, bottom: 0, right: 0)
    }

    /// Which of the toolbar's two backgrounds is showing.
    ///
    /// At the scroll origin the titlebar draws its own material — an opaque band in the system's
    /// light or dark color, with nothing of the page behind it. Once the page has scrolled under
    /// the toolbar the titlebar goes transparent, and the system's treatment of a transparent
    /// titlebar softens whatever is passing beneath: the frosted look.
    ///
    /// Deliberately not a view of our own laid over the strip. That was tried, and an opaque
    /// sibling sitting on top of the web view stopped it painting altogether — the whole page
    /// came up blank, not just the 52 points the view actually covered, because WebKit treats
    /// being covered as being occluded and stops drawing. Driving the titlebar's own background
    /// leaves nothing on top of the web view at all.
    private func updateTitlebarBackdrop() {
        // The Empty Page (#16) is its own full-bleed composition — letting it run up under a
        // transparent toolbar is the point, so it never gets the opaque band.
        let isShowingWebContent = !webView.isHidden
        window.titlebarAppearsTransparent = !(isShowingWebContent && isPageAtTop)
    }

    /// Reports whether the page sits at its scroll origin. There is nothing on `WKWebView` to
    /// observe for this, so the page tells us. Installed once: a `WKUserScript` is re-injected
    /// into every document the web view loads, so each new page gets its own listener for free.
    private func installPageScrollReporting() {
        let controller = webView.configuration.userContentController
        controller.add(PageScrollReporter { [weak self] atTop in
            guard let self, atTop != self.isPageAtTop else { return }
            self.isPageAtTop = atTop
            self.updateTitlebarBackdrop()
        }, name: Self.scrollReportName)
        controller.addUserScript(
            WKUserScript(source: Self.scrollReportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    fileprivate static let scrollReportName = "mochiPageScroll"
    /// Only posts on a change, so an inertial scroll doesn't flood the bridge.
    private static let scrollReportScript = """
    (() => {
      let last = null;
      const report = () => {
        const atTop = (window.scrollY || document.documentElement.scrollTop || 0) <= 2;
        if (atTop !== last) {
          last = atTop;
          window.webkit.messageHandlers.\(AppKitWidgetWindowHandle.scrollReportName).postMessage(atTop);
        }
      };
      document.addEventListener("scroll", report, { passive: true });
      window.addEventListener("resize", report);
      report();
    })();
    """

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
        // While the user is typing, every input this method reads is stale by definition — the
        // field's text is theirs, not the page's (`AddressFieldPresenter.acceptsPageDrivenUpdates`).
        // Without this, a background load flipping `isLoading` would take `isEditable` away
        // mid-word, and a title KVO tick or the mouse drifting off the field would put the URL
        // back over a half-typed address.
        guard AddressFieldPresenter.acceptsPageDrivenUpdates(
            hasActiveEditingSession: controls.addressField.currentEditor() != nil)
        else { return }
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

    /// Brings the address field's two icons in step with whether a page is loaded: the embedded
    /// refresh affordance at the trailing edge (ADR-0011, shown or hidden per
    /// `AddressFieldPresenter`, with the text area's trailing inset kept in step so the two never
    /// overlap) and the leading glyph (`DesignTokens.addressFieldGlyph` — lock once loaded,
    /// magnifying glass on the Empty Page). Both are driven purely by `hasNavigatedAtLeastOnce`
    /// — deliberately not by `isLoading`, since neither is a stop/cancel toggle.
    private func updateAddressFieldIcons() {
        let isVisible = AddressFieldPresenter.showsEmbeddedRefreshIcon(
            hasNavigatedAtLeastOnce: hasNavigatedAtLeastOnce)
        controls.addressFieldRefreshButton.isHidden = !isVisible
        (controls.addressField.cell as? AddressFieldCell)?.trailingInset =
            isVisible ? Self.embeddedRefreshIconReservedWidth : 0
        let leadingState = DesignTokens.addressFieldLeadingIcon(
            hasLoadedPage: hasNavigatedAtLeastOnce, hasSiteIcon: siteIcon != nil)
        if leadingState == .siteIcon, let siteIcon {
            controls.addressFieldLeadingIconView.image = siteIcon
        } else {
            guard let symbolName = leadingState.symbolName else { return }
            controls.addressFieldLeadingIconView.image = ToolbarStyle.symbolImage(
                symbolName, accessibilityDescription: leadingState.accessibilityLabel,
                pointSize: ToolbarStyle.GlyphSize.addressFieldLeading)
        }
        controls.addressFieldLeadingIconView.setAccessibilityLabel(leadingState.accessibilityLabel)
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
    /// places a cursor in it, rather than requiring a second click.
    ///
    /// A load in flight is no longer a reason to refuse: `AddressFieldPresenter` now ranks editing
    /// above loading, so a heavy page can't leave the address bar unclickable while it finishes.
    /// What that used to protect against is handled by the deferred check instead — if AppKit ends
    /// up not granting the field an editor, there is no blur notification coming to clear the flag,
    /// and the bar would sit in its editable-URL state indefinitely.
    private func beginEditingAddressField() {
        guard hasNavigatedAtLeastOnce, !isEditingAddressField else { return }
        isEditingAddressField = true
        updateAddressFieldDisplay()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditingAddressField,
                self.controls.addressField.currentEditor() == nil
            else { return }
            self.isEditingAddressField = false
            self.updateAddressFieldDisplay()
        }
    }

    /// Leaves the editable state — but only once the field has genuinely lost its field editor.
    ///
    /// AppKit posts `textDidEndEditing:` *while it is installing* the field editor this very
    /// click asked for (measured: it arrives inside `super.mouseDown`, before
    /// `controlTextDidBeginEditing` has fired at all). Acting on it synchronously tore down the
    /// session that was still being built: the field kept the editor but was set back to
    /// `isEditable = false`, so the caret appeared and then every keystroke was dropped — the
    /// address bar looked focused and could not be typed into. Deferring one runloop turn lets
    /// AppKit finish, and `currentEditor()` then answers the real question: still editing (this
    /// was the install-time notification — ignore it), or truly blurred/submitted.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === controls.addressField else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.controls.addressField.currentEditor() == nil else { return }
            self.isEditingAddressField = false
            self.updateAddressFieldDisplay()
        }
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

    func setGhostModeToggleRequestedHandler(_ handler: @escaping () -> Void) {
        ghostModeToggleRequestedHandler = handler
    }

    /// Giving up focus on this entry path (#44) is `Orchestrator`'s call, made via
    /// `PlatformOps.deactivateApp()` in its `onGhostModeToggleRequested` handler, not this view's
    /// — mirrors how taking focus back (`showWindow`'s `NSApp.activate()`) is routed through
    /// `PlatformOps` rather than decided by whichever view happens to trigger it (code review
    /// finding, #44 review: the original version called `NSApp.deactivate()` straight from this
    /// `@objc` action, an untestable platform-only special case for a concern everything else in
    /// this codebase treats as core-owned policy).
    @objc private func handleGhostModeToggleRequested() {
        ghostModeToggleRequestedHandler?()
    }

    func injectScript(_ source: String) {
        webView.evaluateJavaScript(source, completionHandler: nil)
    }

    /// Switches the content area back to `webView` (in case the Empty Page was showing) and loads
    /// `url` into it — used both for the resolved startup URL and every later address-bar
    /// navigation, so navigating away from the Empty Page always brings the page back on top.
    func loadURL(_ url: URL) {
        emptyPageHostingView.isHidden = true
        errorPageHostingView.isHidden = true
        webView.isHidden = false
        hasNavigatedAtLeastOnce = true
        currentURL = url
        siteIcon = nil
        // A new document starts at its own origin; the previous page's scroll position says
        // nothing about it, and the injected reporter only speaks up once the new one has loaded.
        isPageAtTop = true
        webView.load(URLRequest(url: url))
        updateTitlebarBackdrop()
        updateAddressFieldIcons()
        updateAddressFieldDisplay()
    }

    /// Switches the content area to the Empty Page's native content, hiding `webView` — the
    /// counterpart to `loadURL`. Also resets `errorPageHostingView` like every other transition
    /// between this shared container's three layers does, even though no caller reaches this
    /// while an error page is showing today — leaving it out here was a real inconsistency the
    /// next caller could trip over (code review finding, #38 review).
    func showEmptyPage() {
        defer { updateTitlebarBackdrop() }
        webView.isHidden = true
        errorPageHostingView.isHidden = true
        emptyPageHostingView.isHidden = false
    }

    /// Switches the content area to the error page (#38), showing `message` alongside whatever
    /// URL was loading. "重试" re-issues `loadURL` for the failed URL directly rather than
    /// round-tripping through the core — it's acting on the same web view this handle already
    /// owns, same as the toolbar's embedded refresh button. Deliberately `loadURL`, not
    /// `webView.reload()`: `reload()` needs an existing *committed* navigation to act on, so it
    /// silently no-ops when the very first navigation Mochi ever attempts is the one that failed
    /// (code review finding, #38 review) — `loadURL` has no such precondition and also correctly
    /// re-hides this same error page on the retry attempt.
    func showErrorPage(message: String) {
        let failedURL = currentURL
        errorPageHostingView.rootView = ErrorPageView(
            failedURL: failedURL?.absoluteString ?? "", message: message,
            onRetry: { [weak self] in
                guard let failedURL else { return }
                self?.loadURL(failedURL)
            }
        )
        webView.isHidden = true
        errorPageHostingView.isHidden = false
    }

    func setNavigationFinishedHandler(_ handler: @escaping () -> Void) {
        navigationFinishedHandler = handler
    }

    func setNavigationFailedHandler(_ handler: @escaping (String) -> Void) {
        navigationFailedHandler = handler
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A retry (which reloads `webView` directly, bypassing `loadURL`) needs the error page
        // cleared here — `loadURL` only covers navigations that went through it.
        errorPageHostingView.isHidden = true
        webView.isHidden = false
        fetchSiteIcon()
        navigationFinishedHandler?()
    }

    /// Fetches the loaded page's favicon for the address bar's leading icon. Deliberately after
    /// `didFinish` rather than on commit: the icon links are read out of the live DOM, and a
    /// single-page app may not have injected them yet at commit time.
    private func fetchSiteIcon() {
        guard let pageURL = webView.url ?? currentURL,
            let requestedOrigin = FaviconLoader.origin(of: pageURL)
        else { return }
        faviconLoader.loadIcon(for: pageURL, in: webView) { [weak self] image in
            guard let self, let image else { return }
            // A slow fetch can land after the user has already moved on; the icon belongs to the
            // origin it was requested for, not to whatever is on screen when it arrives.
            guard let currentOrigin = self.currentURL.flatMap(FaviconLoader.origin(of:)),
                currentOrigin == requestedOrigin
            else { return }
            self.siteIcon = image
            self.updateAddressFieldIcons()
        }
    }

    /// Covers the most common real-world failure (DNS/offline) that `didFail` alone would miss —
    /// it only fires for a navigation that *committed* first.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    /// Filters out cancellation (`NSURLErrorCancelled`) — the user changing the address mid-load
    /// or clicking a new link both abort the in-flight navigation this way, and neither should
    /// flash an error page for what isn't really a failure.
    private func handleNavigationFailure(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        navigationFailedHandler?(error.localizedDescription)
    }

    func setToolbarVisible(_ visible: Bool) {
        window.toolbar?.isVisible = visible
    }

    /// Both close entries — the red button and `⌘W` via `closeWidgetWindow` — land here (#42):
    /// the core's handler runs first (it persists geometry and forgets this window), then the web
    /// content is torn down explicitly. Closing is closing: the page must stop (video, audio)
    /// right now, not whenever the last reference to this handle happens to drop.
    func windowWillClose(_ notification: Notification) {
        willCloseHandler?()
        tearDownWebContent()
    }

    /// Stops the page for good. `loadHTMLString("")` is what actually silences a playing
    /// `<video>`/`<audio>` — `stopLoading()` alone only aborts in-flight requests. Detaching the
    /// delegate first keeps that blank load from reporting back as a navigation.
    private func tearDownWebContent() {
        navigationObservations = []
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    /// The frame `captureWindowState` should persist — `window.frame` itself during element
    /// fullscreen (#38), otherwise the frame from just before entering it.
    var frameToPersist: NSRect {
        var frame = frameBeforeFullscreen ?? window.frame
        frame.size.height += ghostModeHeightReduction
        return frame
    }

    /// A page's own fullscreen button (enabled via `isElementFullscreenEnabled`, #38) puts the
    /// *whole window* into native fullscreen on macOS — WebKit drives this through the window's
    /// standard `toggleFullScreen:` machinery, not a separate view-level fullscreen concept, so
    /// this ordinary `NSWindowDelegate` hook is where it's observable.
    func windowWillEnterFullScreen(_ notification: Notification) {
        frameBeforeFullscreen = window.frame
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        frameBeforeFullscreen = nil
    }

    /// Covers the abort path `windowDidExitFullScreen` never reaches: if entering fullscreen is
    /// cancelled partway (a distinct `NSWindowDelegate` callback, taking the window directly
    /// rather than a `Notification`), the window never successfully entered fullscreen, so it
    /// never later exits either — leaving `frameBeforeFullscreen` stuck forever and
    /// `frameToPersist`/`captureWindowState` returning a stale frame until the app restarts
    /// (code review finding, #38 review).
    func windowDidFailToEnterFullScreen(_ failedWindow: NSWindow) {
        frameBeforeFullscreen = nil
    }

    /// Ghost Mode drops the toolbar row from the window itself, without the page ever noticing.
    /// The window's top edge comes down by the row's height (the origin is the bottom-left, so
    /// shrinking the height with the origin held does exactly that), but the content — web view,
    /// Empty Page, error page — keeps its height, and the web view its `obscuredContentInsets`:
    /// the obscured strip simply ends up above the window and is clipped. Nothing WebKit can see changes, so the page gets no `resize` and
    /// can't flash. An earlier version zeroed the inset instead, and the inset and the frame
    /// reach WebKit separately — for a moment the page had the whole old height and reflowed.
    /// Leaving Ghost Mode raises the top edge back up and re-pins the content to it.
    func setNativeChromeVisible(_ visible: Bool) {
        if visible {
            window.styleMask.insert(.titled)
            // Dropping `.titled` makes AppKit discard the window's toolbar outright — measured:
            // `window.toolbar` reads back `nil` in Ghost Mode and stays `nil` when `.titled`
            // returns, so Normal Mode came back with bare traffic lights and no toolbar at all.
            // Putting the retained one back is the only way it returns. (`.fullSizeContentView`
            // survives the round trip; only the toolbar is lost.)
            if window.toolbar == nil {
                window.toolbar = normalModeToolbar
            }
            if ghostModeHeightReduction > 0 {
                var frame = window.frame
                frame.size.height += ghostModeHeightReduction
                ghostModeHeightReduction = 0
                window.setFrame(frame, display: false)
            }
            contentContainerGhostModeHeight.isActive = false
            contentContainerTopConstraint.isActive = true
            contentTopInset.constant = appliedTitlebarHeight
            isNativeChromeHidden = false
            updateTitlebarMetrics()
        } else {
            isNativeChromeHidden = true
            // A fullscreen window's frame is the screen's, not ours to shrink.
            let toolbarHeight = window.styleMask.contains(.fullScreen) ? 0 : appliedTitlebarHeight
            // Pin the height before anything resizes, so no intermediate layout can squeeze it.
            contentContainerGhostModeHeight.constant = webView.superview!.frame.height
            contentContainerTopConstraint.isActive = false
            contentContainerGhostModeHeight.isActive = true
            // The progress bar belongs at the page's visible top, which is now the window's.
            contentTopInset.constant = 0
            window.styleMask.remove(.titled)
            if toolbarHeight > 0 {
                var frame = window.frame
                frame.size.height -= toolbarHeight
                ghostModeHeightReduction = toolbarHeight
                window.setFrame(frame, display: false)
            }
        }
        updateTitlebarBackdrop()
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

    func setMouseInsideChangedHandler(_ handler: @escaping (Bool) -> Void) {
        mouseInsideChangedHandler = handler
    }

    func setSnapEnabled(_ enabled: Bool) {
        (window as? MochiWidgetWindow)?.isSnapEnabled = enabled
    }

    /// A tracking area on the whole content view is what lets Ghost Mode detect the mouse moving
    /// into and back out of the widget (#8) even though the window ignores mouse events at the
    /// time — AppKit evaluates tracking-rect enter/exit from raw cursor position, independent of
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
        mouseInsideChangedHandler?(true)
    }

    @objc private func mouseExited(with event: NSEvent) {
        mouseInsideChangedHandler?(false)
    }

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
        // into the system's "更多工具栏项" overflow popup first. Three tiers (#44): settings
        // collapses first (`.low`) — a low-frequency, app-level entry point with two other
        // affordances (⌘, and the tray) — Ghost Mode sits above it at the default `.standard` so
        // it survives longer, and the address field/navigation control sit at `.high` so they are
        // never candidates at all. `label` is what an item is called once it lands in the
        // overflow menu — it stays invisible in the toolbar itself, which runs in `.iconOnly`
        // display mode.
        switch itemIdentifier {
        case Self.navigationItemID:
            item.view = controls.navigationControl
            item.label = "后退/前进"
            item.visibilityPriority = .high
        case Self.addressItemID:
            item.view = controls.addressFieldContainer
            item.label = "地址"
            item.visibilityPriority = .high
        case Self.ghostModeItemID:
            // A stock image+action item, not a custom view (#44) — deliberately, since this
            // button never has an active state to reflect: Ghost Mode hides the whole toolbar the
            // moment it's entered, so nobody could ever see it drawn "on". Same reasoning as
            // settings below, just for a different reason (that one has no active state to begin
            // with; this one has one it can never display).
            item.image = ToolbarStyle.ghostImage(
                pointSize: ToolbarStyle.GlyphSize.toolbarItem, accessibilityDescription: "进入 Ghost Mode")
            item.target = self
            item.action = #selector(handleGhostModeToggleRequested)
            item.toolTip = "进入 Ghost Mode"
            item.label = "Ghost Mode"
            item.visibilityPriority = .standard
        case Self.settingsItemID:
            // A stock image+action item rather than a custom view. It was made one so it would
            // shed into the overflow menu *before* Pin (ADR-0011: AppKit sheds a run of adjacent
            // custom-view items in a single step, so two views could never collapse one at a
            // time); Pin is gone now, but leaving this as a stock item keeps the shipped
            // rendering — a stock item has no `contentTintColor` and no fixed box, so this glyph
            // draws at AppKit's own control tint and metrics rather than `DesignTokens`'
            // `iconPrimary`/`normalModeToolbarButtonDiameter`. That is the *correct* rendering
            // for a toolbar glyph now that this is a system symbol: AppKit's control tint is
            // what every other native toolbar uses, including its inactive-window dimming.
            // docs/design-language.md documents this entry as the "更多" (⋯) affordance.
            item.image = ToolbarStyle.symbolImage(DesignTokens.Symbol.settings, accessibilityDescription: "设置")
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
    var isSnapEnabled = true

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        guard isSnapEnabled else { return constrained }
        // Only snap a pure move — during an active resize the frame's size is still changing,
        // and naively adjusting the origin then would fight the edge the user is dragging.
        guard constrained.size == frame.size else { return constrained }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let snapped = WindowSnapping.snappedFrame(WindowFrame(cgRect: constrained), toEdgesOf: screens)
        return snapped.cgRect
    }
}

public final class AppKitPlatformOps: PlatformOps {
    /// Retains the tray icon's `NSStatusItem` and its menu's `MenuItemActionTarget`s for as long
    /// as the tray exists — `NSStatusBar` doesn't keep the status item alive on its own, and
    /// `NSMenuItem.target` doesn't retain its target either.
    private var tray: (statusItem: NSStatusItem, targets: [MenuItemActionTarget])?
    private var reopenRequestedHandler: (() -> Void)?

    public init() {}

    /// `AppDelegate`'s `applicationShouldHandleReopen` (#42) — the Dock-icon click — forwards
    /// here; there is no notification for it, only that delegate callback, so the app target has
    /// to hand it over explicitly.
    public func handleApplicationReopen() {
        reopenRequestedHandler?()
    }

    public func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle {
        let rect = NSRect(x: initialFrame.x, y: initialFrame.y, width: initialFrame.width, height: initialFrame.height)
        // Element Fullscreen (#38) is off by default on macOS — without it, a page's own
        // fullscreen button silently does nothing. Picture-in-Picture needs no configuration
        // here at all: `allowsPictureInPictureMediaPlayback` is iOS-only (there is no macOS
        // equivalent — checked against the WebKit headers), and macOS WKWebView already shows a
        // native video element's own PiP control by default with nothing in this configuration
        // disabling it.
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Set before anything loads — see `normalModeToolbarRowHeight`.
        webView.obscuredContentInsets = NSEdgeInsets(
            top: DesignTokens.Layout.normalModeToolbarRowHeight, left: 0, bottom: 0, right: 0)

        let emptyPageHostingView = NSHostingView(rootView: EmptyPageView())
        emptyPageHostingView.translatesAutoresizingMaskIntoConstraints = false
        emptyPageHostingView.isHidden = true

        // The error page (#38) starts with placeholder content — `showErrorPage(message:)`
        // replaces `rootView` with the real failure before ever making this visible.
        let errorPageHostingView = NSHostingView(rootView: ErrorPageView(failedURL: "", message: "", onRetry: {}))
        errorPageHostingView.translatesAutoresizingMaskIntoConstraints = false
        errorPageHostingView.isHidden = true

        // `webView`, `emptyPageHostingView` (#16), and `errorPageHostingView` (#38) share this
        // container, each pinned to fill it completely — exactly one is ever visible at a time
        // (see `loadURL`/`showEmptyPage`/`showErrorPage`).
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(webView)
        contentContainer.addSubview(emptyPageHostingView)
        contentContainer.addSubview(errorPageHostingView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            emptyPageHostingView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            emptyPageHostingView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            emptyPageHostingView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            emptyPageHostingView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            errorPageHostingView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            errorPageHostingView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            errorPageHostingView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            errorPageHostingView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        let controls = makeToolbarControls()
        let progressBar = makeLoadingProgressBar()

        // The progress bar overlays the top edge of the content area (added after it, so it
        // draws on top) instead of occupying its own row — it takes no layout space while hidden.
        // The content runs the full height of the window (`.fullSizeContentView`), so the page can
        // scroll up behind the toolbar. What keeps its *layout* clear of the toolbar is
        // `obscuredContentInsets`, applied in `updateTitlebarMetrics` — not a smaller frame, which
        // is why changing the toolbar's background never resizes anything. Nothing is ever layered
        // on top of the web view: see `updateTitlebarBackdrop`.
        let rootView = NSView()
        let contentContainerTopConstraint = contentContainer.topAnchor.constraint(equalTo: rootView.topAnchor)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(contentContainer)
        rootView.addSubview(progressBar.view)
        // The progress bar belongs under the toolbar, not behind it.
        let contentTopInset = progressBar.view.topAnchor.constraint(
            equalTo: rootView.topAnchor, constant: DesignTokens.Layout.normalModeToolbarRowHeight)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentContainerTopConstraint,
            contentContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            progressBar.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentTopInset,
        ])

        let window = MochiWidgetWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // ADR-0009: traffic lights + toolbar content share one native row, rendered with the
        // system's own Liquid Glass material — no `NSGlassEffectView` wrapper needed here.
        // Whether the titlebar draws that material or goes transparent is `updateTitlebarBackdrop`'s
        // call, and it tracks the page's scroll position.
        // The handle owns this window through ARC (#42): AppKit's default of releasing a closed
        // window itself would double-free it under Swift. It is deallocated when `Orchestrator`
        // drops the handle from its will-close callback.
        window.isReleasedWhenClosed = false
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
            emptyPageHostingView: emptyPageHostingView, errorPageHostingView: errorPageHostingView,
            progressBar: progressBar, contentTopInset: contentTopInset,
            contentContainerTopConstraint: contentContainerTopConstraint
        )

        let toolbar = NSToolbar(identifier: "MochiNormalModeToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.delegate = handle
        window.toolbar = toolbar
        handle.normalModeToolbar = toolbar

        return handle
    }

    /// Builds the Normal Mode toolbar's controls (ADR-0009/ADR-0011) — a rounded-bezel `NSTextField`
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
        // The rounded bezel is what keeps the Safari-like capsule shape now that this is a plain
        // text field. It is also the variant whose focus ring draws *outside* the border instead
        // of over it (measured against `.squareBezel` and against `NSSearchField`).
        addressField.bezelStyle = .roundedBezel
        addressField.isBezeled = true
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
        // The Empty Page (#16) hasn't navigated yet, so the field stays a plain, freely-editable
        // URL box until `hasNavigatedAtLeastOnce` flips — see `AppKitWidgetWindowHandle.loadURL`.
        addressField.isEditable = true

        // The leading site icon: the page's favicon, or a symbol standing in for it
        // (`updateAddressFieldIcons` owns which). A subview rather than anything cell-owned, so
        // nothing rebuilds it behind our back.
        let leadingIconView = NSImageView()
        leadingIconView.translatesAutoresizingMaskIntoConstraints = false
        leadingIconView.imageScaling = .scaleProportionallyUpOrDown
        leadingIconView.image = ToolbarStyle.symbolImage(
            DesignTokens.AddressFieldLeadingIcon.search.symbolName!,
            accessibilityDescription: DesignTokens.AddressFieldLeadingIcon.search.accessibilityLabel,
            pointSize: ToolbarStyle.GlyphSize.addressFieldLeading)
        addressField.addSubview(leadingIconView)
        let leadingPadding = DesignTokens.Layout.addressFieldLeadingIconLeadingPadding
        let leadingDiameter = DesignTokens.Layout.addressFieldLeadingIconDiameter
        NSLayoutConstraint.activate([
            leadingIconView.leadingAnchor.constraint(
                equalTo: addressField.leadingAnchor, constant: leadingPadding),
            leadingIconView.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            leadingIconView.widthAnchor.constraint(equalToConstant: leadingDiameter),
            leadingIconView.heightAnchor.constraint(equalToConstant: leadingDiameter),
        ])
        // Text starts after the icon. Constant, unlike the trailing inset — the icon is always
        // there in some form, whereas refresh is hidden until the first navigation.
        (addressField.cell as? AddressFieldCell)?.leadingInset = leadingPadding + leadingDiameter

        // Refresh lives inside the field now (ADR-0011) rather than as a standalone
        // `NSToolbarItem`: a plain subview pinned to the trailing edge, with `AddressFieldCell`
        // shrinking the text area by the matching amount. Visibility (hidden until the first real
        // navigation) is owned by `updateAddressFieldIcons`.
        let addressFieldRefreshButton = toolbarButton(
            image: ToolbarStyle.symbolImage(
                DesignTokens.Symbol.refresh, accessibilityDescription: "刷新",
                pointSize: ToolbarStyle.GlyphSize.addressFieldEmbedded),
            diameter: DesignTokens.Layout.addressFieldEmbeddedIconDiameter)
        addressField.addSubview(addressFieldRefreshButton)
        NSLayoutConstraint.activate([
            addressFieldRefreshButton.trailingAnchor.constraint(
                equalTo: addressField.trailingAnchor,
                constant: -DesignTokens.Layout.addressFieldEmbeddedIconTrailingPadding),
            addressFieldRefreshButton.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
        ])

        // The toolbar item hosts this container rather than the field itself, so AppKit's focus
        // ring — drawn outside the field's bounds — has room instead of being sliced flat against
        // the item viewer's edge (`addressFieldFocusRingInset`).
        let addressFieldContainer = NSView()
        addressFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        addressFieldContainer.addSubview(addressField)
        let ringInset = DesignTokens.Layout.addressFieldFocusRingInset
        NSLayoutConstraint.activate([
            addressField.leadingAnchor.constraint(
                equalTo: addressFieldContainer.leadingAnchor, constant: ringInset),
            addressField.trailingAnchor.constraint(
                equalTo: addressFieldContainer.trailingAnchor, constant: -ringInset),
            addressField.topAnchor.constraint(
                equalTo: addressFieldContainer.topAnchor, constant: ringInset),
            addressField.bottomAnchor.constraint(
                equalTo: addressFieldContainer.bottomAnchor, constant: -ringInset),
        ])

        return ToolbarControls(
            navigationControl: makeNavigationControl(),
            addressField: addressField,
            addressFieldContainer: addressFieldContainer,
            addressFieldLeadingIconView: leadingIconView,
            addressFieldRefreshButton: addressFieldRefreshButton
        )
    }

    /// Back and forward as one joined native `NSSegmentedControl` (ADR-0011) instead of two
    /// independent buttons, matching Safari's own control, carrying the system's own
    /// `chevron.left`/`chevron.right` symbols. `.momentary` tracking keeps both segments
    /// push-button-like: neither stays visually "selected" after a click, since these aren't a
    /// mutually-exclusive choice.
    private func makeNavigationControl() -> NSSegmentedControl {
        let control = NSSegmentedControl(
            images: [
                ToolbarStyle.symbolImage(DesignTokens.Symbol.back, accessibilityDescription: "后退"),
                ToolbarStyle.symbolImage(DesignTokens.Symbol.forward, accessibilityDescription: "前进"),
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

    private func toolbarButton(image: NSImage, diameter: Double) -> NSButton {
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
        return WindowState(frame: WindowFrame(cgRect: handle.frameToPersist), zoom: handle.webView.pageZoom)
    }

    public func onWindowWillClose(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setWillCloseHandler(handler)
    }

    /// `NSWindow.close()` — the same call the red close button makes — so `windowWillClose` fires
    /// once and does the whole teardown for either entry (#42).
    public func closeWidgetWindow(_ window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.window.close()
    }

    public func onReopenRequested(perform handler: @escaping () -> Void) {
        reopenRequestedHandler = handler
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

    public func onGhostModeToggleRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setGhostModeToggleRequestedHandler(handler)
    }

    public func deactivateApp() {
        NSApp.deactivate()
    }

    public func injectScript(_ source: String, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.injectScript(source)
    }

    public func onNavigationFinished(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setNavigationFinishedHandler(handler)
    }

    public func onNavigationFailed(_ window: WidgetWindowHandle, perform handler: @escaping (String) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setNavigationFailedHandler(handler)
    }

    public func showErrorPageContent(message: String, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.showErrorPage(message: message)
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

    public func onMouseInsideChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setMouseInsideChangedHandler(handler)
    }

    @discardableResult
    public func registerGlobalHotkey(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool {
        GlobalHotkeyRegistry.shared.register(hotkey, perform: handler)
    }

    public func unregisterGlobalHotkey(_ hotkey: Hotkey) {
        GlobalHotkeyRegistry.shared.unregister(hotkey)
    }

    public func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    public func setSnapEnabled(_ enabled: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setSnapEnabled(enabled)
    }

    /// The tray glyph is `MochiGlyph` — the brand mark the app icon also wears, rather than the
    /// ghost that used to stand in here (ADR-0015). The point size is pinned rather than left at
    /// the toolbar's, because a status item draws its image at that image's own size inside a
    /// 22pt menu bar; `NSStatusItem.squareLength` then makes the item only as wide as the bar is
    /// thick, which is what bounds the glyph's ink aspect ratio.
    public func createTrayIcon(items: [TrayMenuItem]) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = ToolbarStyle.mochiImage(
            pointSize: ToolbarStyle.GlyphSize.tray, accessibilityDescription: "Mochi")

        let menu = NSMenu()
        var targets: [MenuItemActionTarget] = []
        for item in items {
            let target = MenuItemActionTarget(action: item.action)
            targets.append(target)
            let menuItem = NSMenuItem(title: item.title, action: #selector(MenuItemActionTarget.invoke), keyEquivalent: "")
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
