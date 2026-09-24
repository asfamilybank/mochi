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

    /// `iconTint` under the pointer — full-strength rather than `iconPrimary`'s slight fade.
    static func iconHoverTint() -> NSColor {
        dynamicColor(light: DesignTokens.glassPalette(dark: false).textPrimary, dark: DesignTokens.glassPalette(dark: true).textPrimary)
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

/// The Smart Address Field's text (#18) — just the text. Borderless and background-free: the
/// capsule, the site icon and the refresh affordance all belong to `AddressBarView`, which hosts
/// this as one of three siblings (Safari's own layout, read off its accessibility tree).
///
/// It is a plain `NSTextField` rather than the `NSSearchField` this started as: the search
/// field's cancel and search button cells are rebuilt by AppKit on every toolbar layout pass, so
/// keeping a custom leading glyph on one and a cleared cancel button on the other meant
/// re-applying both from `layout()` forever — and assigning to either property is itself what
/// provoked the rebuild. Safari's field isn't a search field either (`AXTextField`, no
/// `AXSearchField` subrole).
private final class AddressField: NSTextField {
    /// Only reached while nobody is editing — once a field editor is installed, it takes the
    /// clicks itself. Every such click is `AddressBarView`'s "activate the bar", the same as a
    /// click on the rim or the icon: the field is about to slide to its editing layout and swap
    /// the title for the URL, so a caret placed under the pointer would land somewhere arbitrary.
    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }
}

/// What the address toolbar item hosts: the capsule, with the site icon, `AddressField` and the
/// refresh affordance laid out inside it as siblings (`AddressBarLayout` decides where).
///
/// Owning the capsule here rather than on the field is what gives the Safari behavior: only the
/// field's own frame can ever show an I-beam, so the rim and both icons keep the arrow cursor;
/// and the field can shrink to its text and sit centered next to the icon while nobody is
/// editing, then widen to the whole middle once clicked. A click anywhere on the capsule while
/// nobody is editing — the rim, the site icon, or the text itself, which `AddressField` forwards —
/// arrives here and is handed to `onActivate`.
///
/// Children are positioned by hand in `layout()`; the container's own size comes solely from its
/// width/height constraints plus the toolbar's spare room. Nothing inside reports an intrinsic
/// width to `NSToolbarItem` — a field that did would make the item collapse its `maxSize` onto the
/// text's fitting size and freeze the bar at its minimum width from the first navigation on
/// (measured, ADR-0011).
private final class AddressBarView: NSView {
    let field = AddressField()
    let leadingIconView = NSImageView()
    let refreshButton: NSButton
    var onActivate: (() -> Void)?

    /// Whether the field is a live input: full-width with the icon at the leading edge, and the
    /// focus ring drawn around the capsule. Otherwise it is an unselectable display of the
    /// title/URL, hugging its text and centered together with the icon. Flipping it animates
    /// between the two layouts.
    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            needsDisplay = true
            animateLayoutChange()
        }
    }

    var isRefreshVisible = true {
        didSet {
            guard isRefreshVisible != oldValue else { return }
            refreshButton.isHidden = !isRefreshVisible
            needsLayout = true
        }
    }

    /// Refresh or stop (#60) — same button, same frame, only its glyph and tooltip change, so the
    /// swap never moves the text.
    var trailingAction: AddressFieldPresenter.EmbeddedTrailingAction = .reload {
        didSet {
            guard trailingAction != oldValue else { return }
            applyTrailingAction()
        }
    }

    func applyTrailingAction() {
        refreshButton.image = ToolbarStyle.symbolImage(
            trailingAction.symbolName, accessibilityDescription: trailingAction.toolTip,
            pointSize: ToolbarStyle.GlyphSize.addressFieldEmbedded)
        refreshButton.toolTip = trailingAction.toolTip
    }

    /// The site icon holds the leading edge (mirroring refresh) instead of travelling with the
    /// text — on a page. The Empty Page's magnifying glass stays centered with its placeholder.
    var pinsIcon = false {
        didSet {
            guard pinsIcon != oldValue else { return }
            needsLayout = true
        }
    }

    /// Measures what the field's text (or its placeholder, when empty) needs, with the field's
    /// own font and a borderless cell's own padding — the field itself can't answer that for its
    /// placeholder.
    private let measuringCell: NSTextFieldCell = {
        let cell = NSTextFieldCell(textCell: "")
        cell.isBordered = false
        cell.isBezeled = false
        return cell
    }()
    private var keyObservers: [NSObjectProtocol] = []

    init(refreshButton: NSButton) {
        self.refreshButton = refreshButton
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        leadingIconView.imageScaling = .scaleProportionallyUpOrDown
        for view in [leadingIconView, field, refreshButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// The capsule itself — inset from the container by `addressFieldFocusRingInset`, which is
    /// where the focus ring is drawn (`NSToolbarItemViewer` leaves a hosted view only 4pt of
    /// horizontal slack, so the ring has to fit inside the item's own bounds).
    private var capsuleRect: NSRect {
        let inset = DesignTokens.Layout.addressFieldFocusRingInset
        return bounds.insetBy(dx: inset, dy: inset)
    }

    override func layout() {
        super.layout()
        let capsule = capsuleRect
        let text = field.stringValue.isEmpty ? (field.placeholderString ?? "") : field.stringValue
        measuringCell.font = field.font
        measuringCell.stringValue = text
        let placement = AddressBarLayout.placement(
            capsuleWidth: Double(capsule.width),
            contentWidth: Double(ceil(measuringCell.cellSize.width)),
            isEditing: isEditing,
            pinsIcon: pinsIcon,
            leadingPadding: DesignTokens.Layout.addressFieldLeadingIconLeadingPadding,
            iconSize: DesignTokens.Layout.addressFieldLeadingIconDiameter,
            iconTextGap: DesignTokens.Layout.addressFieldLeadingIconTextGap,
            trailingReserved: isRefreshVisible
                ? DesignTokens.Layout.addressFieldEmbeddedIconDiameter
                    + DesignTokens.Layout.addressFieldEmbeddedIconTrailingPadding * 2
                : DesignTokens.Layout.addressFieldLeadingIconLeadingPadding)

        let iconSize = DesignTokens.Layout.addressFieldLeadingIconDiameter
        leadingIconView.frame = backingAligned(NSRect(
            x: capsule.minX + placement.iconMinX, y: capsule.midY - iconSize / 2,
            width: iconSize, height: iconSize))
        let fieldHeight = field.intrinsicContentSize.height
        field.frame = backingAligned(NSRect(
            x: capsule.minX + placement.fieldMinX, y: capsule.midY - fieldHeight / 2,
            width: placement.fieldWidth, height: fieldHeight))
        let refreshSize = DesignTokens.Layout.addressFieldEmbeddedIconDiameter
        refreshButton.frame = backingAligned(NSRect(
            x: capsule.maxX - DesignTokens.Layout.addressFieldEmbeddedIconTrailingPadding - refreshSize,
            y: capsule.midY - refreshSize / 2, width: refreshSize, height: refreshSize))
    }

    /// Slides the icon and the field to wherever `layout()` now puts them. Implicit animation
    /// turns the frame assignments in `layout()` into animated ones, so the geometry still has a
    /// single source; any later layout pass (a title arriving mid-slide) simply lands on the final
    /// frames. Honors Reduce Motion by not animating at all.
    private func animateLayoutChange() {
        needsLayout = true
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Motion.addressBarModeChange
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            layoutSubtreeIfNeeded()
        }
    }

    private func backingAligned(_ rect: NSRect) -> NSRect {
        backingAlignedRect(rect, options: .alignAllEdgesNearest)
    }

    /// The focus ring, drawn by hand around the capsule. A focus ring AppKit draws for a view is
    /// clipped to that view's own bounds (measured: a mask covering the capsule drew nothing,
    /// the same mask shrunk inside the field drew fine), and the field is now much smaller than
    /// the capsule — so the ring that used to come with the bezeled field is this container's job.
    override func draw(_ dirtyRect: NSRect) {
        guard isEditing, window?.isKeyWindow == true else { return }
        let capsule = capsuleRect
        let ringWidth = DesignTokens.Layout.addressFieldFocusRingInset
        let ringRect = capsule.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2)
        let ring = NSBezierPath(roundedRect: ringRect, xRadius: ringRect.height / 2, yRadius: ringRect.height / 2)
        ring.lineWidth = ringWidth
        NSColor.keyboardFocusIndicatorColor.setStroke()
        ring.stroke()
    }

    /// The ring only shows while the window is key, like every system focus ring.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in self?.needsDisplay = true })
        }
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}

/// An icon button inside the address bar's capsule that responds to the pointer: the icon deepens
/// and a faint disc appears behind it, the way Safari's in-field buttons react on hover.
private final class HoverIconButton: NSButton {
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            contentTintColor = isHovered ? ToolbarStyle.iconHoverTint() : ToolbarStyle.iconTint()
            needsDisplay = true
        }
    }
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// Hidden under the pointer (refresh on the Empty Page) delivers no exit event, so the hover
    /// state would otherwise still be lit the next time the button appears.
    override func viewDidHide() {
        super.viewDidHide()
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            ToolbarStyle.dynamicColor(
                light: DesignTokens.addressBarIconHoverBackground(dark: false),
                dark: DesignTokens.addressBarIconHoverBackground(dark: true)
            ).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
        super.draw(dirtyRect)
    }
}

/// The Empty Page's and the error page's host. A click on native page content takes focus off
/// the address bar the way a click on a web page does: `WKWebView` makes itself first responder
/// when clicked, so the bar's field editor goes away, but a SwiftUI host never accepts first
/// responder and a click on it would otherwise leave the bar focused indefinitely. Buttons in the
/// page (the error page's 重试) still get the click — this only clears focus before passing it on.
private final class NativePageHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
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
    /// The address toolbar item's view. Built once here rather than in `itemForItemIdentifier`,
    /// which AppKit may call again for the same identifier — a fresh bar per call would re-parent
    /// its field and lose its wiring.
    let addressBar: AddressBarView
    /// The address bar's upper width bound. Normally `addressFieldMaxWidth`; `centerAddressBar`
    /// lowers it whenever the window is too narrow to hold a bar that wide on its center.
    let addressBarMaxWidth: NSLayoutConstraint
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
/// Field (with refresh embedded at its trailing edge), and the Ghost Mode entry all on one row,
/// rendered with the system's own Liquid Glass material — sitting above the WKWebView. No title
/// text is drawn next to the traffic lights (`titleVisibility = .hidden`). Nothing collapses into
/// the system's overflow menu: a narrow window hides the Ghost Mode button outright
/// (`layoutToolbarItems`), and `normalModeWindowMinWidth` keeps the rest in place.
///
/// Colors, corner radii, spacing, symbol names, and the one bespoke glyph all come from
/// `DesignTokens`/`GhostGlyph` (#17) — nothing here writes its own numbers.
final class AppKitWidgetWindowHandle: NSObject, WidgetWindowHandle, NSWindowDelegate, NSTextFieldDelegate, WKNavigationDelegate {
    private static let navigationItemID = NSToolbarItem.Identifier("com.mochi.toolbar.navigation")
    fileprivate static let addressItemID = NSToolbarItem.Identifier("com.mochi.toolbar.address")
    private static let ghostModeItemID = NSToolbarItem.Identifier("com.mochi.toolbar.ghostMode")
    /// The Normal Mode toolbar's fixed item order (`DesignTokens.normalModeToolbarOrder`).
    /// Three items of our own: back and forward share one segmented control, and refresh is
    /// embedded in the address field rather than being an item of its own (ADR-0011).
    ///
    /// The address field is the toolbar's centered item (`centeredItemIdentifiers`), so it sits on
    /// the window's horizontal center whatever the traffic lights and the trailing items weigh.
    /// The two `.flexibleSpace`s take the slack on either side of it: the leading one sits *before*
    /// the navigation control, so back/forward hug the field's leading edge instead of the traffic
    /// lights, and the trailing one keeps Ghost Mode (#44) flush with the window's trailing edge.
    /// There is no settings item: ⌘, and the tray already open the panel, and a lone collapsible
    /// item only ever produced an overflow "»" holding a single entry.
    private static let toolbarItemOrder: [NSToolbarItem.Identifier] = [
        .flexibleSpace, navigationItemID, addressItemID, .flexibleSpace, ghostModeItemID,
    ]

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
    private var ghostModeToggleRequestedHandler: (() -> Void)?
    private var navigationFinishedHandler: (() -> Void)?
    private var navigationFailedHandler: ((String) -> Void)?
    private var mouseInsideChangedHandler: ((Bool) -> Void)?
    private var pageTitleChangedHandler: ((String?) -> Void)?
    private var emptyPageVisibilityChangedHandler: ((Bool) -> Void)?
    private var loadingStateChangedHandler: ((Bool) -> Void)?
    private var loadingProgressChangedHandler: ((Double) -> Void)?
    /// Set on `windowWillEnterFullScreen`, cleared on `windowDidExitFullScreen` — `window.frame`
    /// itself is the screen-filling fullscreen frame for the whole time in between, so anything
    /// reading a persistable window geometry (`frameToPersist`) needs this instead. Without it, a
    /// persist that lands mid-fullscreen (e.g. ⌘Q) would save a frame that fills the screen, and
    /// the next launch would start the window that way (#38).
    private var frameBeforeFullscreen: NSRect?
    /// Whether a real navigation (`loadURL`) has ever happened — before that the bar is the Empty
    /// Page's (#16): magnifying glass, placeholder, no refresh affordance.
    private var hasNavigatedAtLeastOnce = false
    /// Whether this session opened on the Empty Page — the only case where there is one to go
    /// back to (`EmptyPageHistory`).
    private var startedOnEmptyPage = false
    /// The Empty Page is on screen — at startup, or reached by going back.
    private var isShowingEmptyPage = false
    /// Which layer going back onto the Empty Page hid, so forward can put the same one back.
    private var emptyPageCoveredErrorPage = false
    /// A page (or its error page) is what the bar describes: neither the startup Empty Page nor
    /// one returned to by going back. Drives the leading icon and the refresh affordance.
    private var isShowingPage: Bool { hasNavigatedAtLeastOnce && !isShowingEmptyPage }
    private var isLoading = false
    /// Mirrors `webView.url`, but updated *synchronously* in `loadURL` — `webView.url` itself only
    /// updates once WKWebView actually commits the navigation, which lags a KVO tick or more
    /// behind the `loadURL`/`isLoading` transition, so reading `webView.url` directly in
    /// `updateAddressFieldDisplay()` could show the previous page's (stale) URL/host for a moment.
    private var currentURL: URL?
    private var isHoveringAddressField = false
    private var isEditingAddressField = false
    private let contentTopInset: NSLayoutConstraint
    /// The error page's top edge, held below the toolbar strip — its counterpart to the web view's
    /// `obscuredContentInsets` (and to `EmptyPageView.topInset`), kept equal to it, and like it
    /// left alone by Ghost Mode.
    private let nativePageTopConstraints: [NSLayoutConstraint]
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
        nativePageTopConstraints: [NSLayoutConstraint],
        contentContainerTopConstraint: NSLayoutConstraint
    ) {
        self.window = window
        self.webView = webView
        self.controls = controls
        self.emptyPageHostingView = emptyPageHostingView
        self.errorPageHostingView = errorPageHostingView
        self.progressBar = progressBar
        self.contentTopInset = contentTopInset
        self.nativePageTopConstraints = nativePageTopConstraints
        self.appliedTitlebarHeight = contentTopInset.constant
        self.contentContainerTopConstraint = contentContainerTopConstraint
        self.contentContainerGhostModeHeight = webView.superview!.heightAnchor.constraint(equalToConstant: 0)
        self.defaultWindowBackgroundColor = window.backgroundColor
        super.init()
        window.delegate = self
        webView.navigationDelegate = self
        installGhostModeMouseTracking()
        installAddressFieldHoverTracking()
        controls.addressBar.field.delegate = self
        controls.addressBar.onActivate = { [weak self] in
            self?.activateAddressField()
        }
        controls.navigationControl.target = self
        controls.navigationControl.action = #selector(navigationSegmentClicked(_:))
        controls.addressBar.refreshButton.target = self
        controls.addressBar.refreshButton.action = #selector(embeddedTrailingButtonClicked)
        observeNavigationState()
        updateAddressFieldIcons()
        updateAddressFieldDisplay()
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
            self?.layoutToolbarItems()
        }
        updateTitlebarMetrics()
        updateTitlebarBackdrop()
    }


    /// Hides the Ghost Mode button ahead of the width the window is *about* to take. AppKit lays
    /// the toolbar out as part of applying the new frame, before `windowDidResize` — so a fast drag
    /// that jumps from above `ghostModeButtonMinWindowWidth` to well below it in one step had that
    /// layout still see the button, sweep it into a "»" for a frame, and only then have
    /// `layoutToolbarItems` hide it. Only hiding happens here: showing the button while the window
    /// is still at its old, narrower width would flash the same "»" on the way out; that waits for
    /// `windowDidResize`, once the room exists.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if frameSize.width < DesignTokens.Layout.ghostModeButtonMinWindowWidth {
            updateGhostModeItemVisibility(forWindowWidth: frameSize.width)
        }
        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        updateTitlebarMetrics()
        layoutToolbarItems()
    }

    /// Fits the toolbar row to the window's width without ever producing an overflow "»":
    ///
    /// - The Ghost Mode button is *hidden* (`NSToolbarItem.isHidden`), not collapsed, below the
    ///   width that holds it (`ghostModeButtonMinWindowWidth`) — Ghost Mode stays reachable from
    ///   its hotkey and the tray. Decided from the width alone: an earlier version un-hid the
    ///   button on every resize, laid the row out and re-hid it if AppKit hadn't fit it, and during
    ///   a live drag AppKit's own later layout passes caught the un-hidden state — the button
    ///   flickered, and a row laid out as if it were there swept the address bar into a "»".
    /// - The address bar is kept on the window's horizontal center. `centeredItemIdentifiers` only
    /// centers an item that fits there at the width its constraints ask for — measured: below
    /// ~860pt the bar held its full `addressFieldMaxWidth` and AppKit simply packed the row to the
    /// left instead, drifting the bar up to 60pt right of center. So the bar is laid out at its
    /// design maximum, and if that lands off-center it is narrowed by twice the offset — exactly
    /// the width that fits centered between the navigation control and the trailing items. Below
    /// `addressFieldMinWidth` it can't shrink further and sits as close to center as the row allows.
    private func updateGhostModeItemVisibility(forWindowWidth width: CGFloat) {
        guard !isNativeChromeHidden,
              let ghostModeItem = window.toolbar?.items.first(where: { $0.itemIdentifier == Self.ghostModeItemID })
        else { return }
        let hidesGhostMode = width < DesignTokens.Layout.ghostModeButtonMinWindowWidth
        if ghostModeItem.isHidden != hidesGhostMode {
            ghostModeItem.isHidden = hidesGhostMode
        }
    }

    private func layoutToolbarItems() {
        let bar = controls.addressBar
        // Not gated on the bar being in the window: a resize straight from wide to narrow has
        // AppKit sweep the address bar *and* Ghost Mode into the overflow menu before this runs,
        // and only hiding Ghost Mode here gets the bar back.
        guard !isNativeChromeHidden, window.toolbar != nil, let frameView = window.contentView?.superview else { return }
        let ringInset = DesignTokens.Layout.addressFieldFocusRingInset
        let maxWidth = DesignTokens.Layout.addressFieldMaxWidth + ringInset * 2
        let minWidth = DesignTokens.Layout.addressFieldMinWidth + ringInset * 2
        controls.addressBarMaxWidth.constant = maxWidth
        updateGhostModeItemVisibility(forWindowWidth: window.frame.width)
        frameView.layoutSubtreeIfNeeded()
        guard bar.window != nil else { return }
        let barFrame = bar.convert(bar.bounds, to: nil)
        let offset = abs(barFrame.midX - window.frame.width / 2)
        guard offset > 0.5 else { return }
        controls.addressBarMaxWidth.constant = max(minWidth, (barFrame.width - offset * 2).rounded(.down))
        frameView.layoutSubtreeIfNeeded()
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
        nativePageTopConstraints.forEach { $0.constant = height }
        emptyPageHostingView.rootView = EmptyPageView(topInset: height)
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
        // The native pages never get the opaque band: the Empty Page (#16) runs full-bleed under a
        // floating, transparent toolbar, and the error page (#38) starts below the strip, which
        // then shows the window's own background.
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
        updateNavigationSegments()
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                self?.updateNavigationSegments()
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                self?.updateNavigationSegments()
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

    private var backStep: EmptyPageHistory.Step? {
        EmptyPageHistory.backStep(
            isShowingEmptyPage: isShowingEmptyPage, startedOnEmptyPage: startedOnEmptyPage,
            webViewCanGoBack: webView.canGoBack)
    }

    private var forwardStep: EmptyPageHistory.Step? {
        EmptyPageHistory.forwardStep(
            isShowingEmptyPage: isShowingEmptyPage, hasPage: hasNavigatedAtLeastOnce,
            webViewCanGoForward: webView.canGoForward)
    }

    /// Back/forward follow `EmptyPageHistory`, which layers the Empty Page underneath the web
    /// view's own list — so besides the web view's `canGoBack`/`canGoForward`, moving onto or off
    /// the Empty Page changes them too.
    private func updateNavigationSegments() {
        setNavigationSegment(NavigationSegment.back, enabled: backStep != nil)
        setNavigationSegment(NavigationSegment.forward, enabled: forwardStep != nil)
    }

    /// Built from the same `backStep`/`forwardStep` the segments above are enabled by, and the
    /// same Empty-Page-aware loading flag the address bar displays — one source for both.
    var navigationState: NavigationState {
        NavigationState(
            canGoBack: backStep != nil, canGoForward: forwardStep != nil,
            isLoading: isLoading && !isShowingEmptyPage)
    }

    @objc private func navigationSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case NavigationSegment.back: goBack()
        case NavigationSegment.forward: goForward()
        default: return
        }
    }

    /// The one back/forward code path (#59): the toolbar segments and the 历史记录 menu's
    /// 返回/前进 (via `PlatformOps.goBack(in:)`/`goForward(in:)`) both land here.
    func goBack() {
        take(backStep, onWebView: webView.goBack)
    }

    func goForward() {
        take(forwardStep, onWebView: webView.goForward)
    }

    private func take(_ step: EmptyPageHistory.Step?, onWebView goWithinWebView: () -> WKNavigation?) {
        switch step {
        case .webView:
            _ = goWithinWebView()
        case .toEmptyPage:
            returnToEmptyPage()
        case .fromEmptyPage:
            leaveEmptyPage()
        case nil:
            break
        }
    }

    /// Back from the oldest page. The page stays loaded in the (hidden) web view — that is what
    /// forward returns to — but anything still in flight is stopped, the way going back stops a
    /// load in any browser, so the progress bar doesn't keep running over the Empty Page.
    private func returnToEmptyPage() {
        emptyPageCoveredErrorPage = !errorPageHostingView.isHidden
        webView.stopLoading()
        showEmptyPage()
    }

    /// Forward from the Empty Page, back onto whichever layer going back hid.
    private func leaveEmptyPage() {
        emptyPageHostingView.isHidden = true
        if emptyPageCoveredErrorPage {
            errorPageHostingView.isHidden = false
        } else {
            webView.isHidden = false
        }
        setShowingEmptyPage(false)
        updateTitlebarBackdrop()
    }

    /// Everything that follows from the Empty Page coming or going: the bar's text and icons, the
    /// back/forward segments, and the window title (via the core's `AddressBarController`).
    private func setShowingEmptyPage(_ showing: Bool) {
        let changed = showing != isShowingEmptyPage
        isShowingEmptyPage = showing
        updateAddressFieldIcons()
        updateAddressFieldDisplay()
        updateNavigationSegments()
        if changed {
            emptyPageVisibilityChangedHandler?(showing)
        }
    }

    func setEmptyPageVisibilityChangedHandler(_ handler: @escaping (Bool) -> Void) {
        emptyPageVisibilityChangedHandler = handler
    }

    /// Not `private` — the target-action for the Normal Mode toolbar's embedded refresh button,
    /// and called directly by `AppKitPlatformOps.reloadPage(in:)` for the default 刷新页面
    /// hotkey (#12).
    @objc func reload() {
        webView.reload()
    }

    /// Called by `AppKitPlatformOps.stopLoading(in:)` (#60) and the embedded stop icon. The
    /// `isLoading` KVO that follows swaps the icon back to refresh.
    func stopLoading() {
        webView.stopLoading()
    }

    /// Acts on what the icon shows right now, not on a fresh read of `isLoading` — a click on
    /// stop must never turn into a reload because the load finished a moment earlier.
    @objc private func embeddedTrailingButtonClicked() {
        switch controls.addressBar.trailingAction {
        case .reload: reload()
        case .stop: stopLoading()
        }
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
    /// needed — this view already owns `webView`) plus the locally-tracked hover/edit flags.
    ///
    /// The Empty Page goes through here too: with no URL, title or host every non-editing state
    /// resolves to an empty text, so the bar shows its placeholder centered and unselectable —
    /// the same "a display until clicked" field as everywhere else, not a bare input box.
    private func updateAddressFieldDisplay() {
        // While the user is typing, every input this method reads is stale by definition — the
        // field's text is theirs, not the page's (`AddressFieldPresenter.acceptsPageDrivenUpdates`).
        // Without this, a background load flipping `isLoading` would take `isEditable` away
        // mid-word, and a title KVO tick or the mouse drifting off the field would put the URL
        // back over a half-typed address.
        guard AddressFieldPresenter.acceptsPageDrivenUpdates(
            hasActiveEditingSession: controls.addressBar.field.currentEditor() != nil)
        else { return }
        // Back on the Empty Page, the page left loaded behind it is not what the bar describes.
        let page = isShowingEmptyPage ? nil : currentURL
        let state = AddressFieldPresenter.displayState(
            isLoading: isLoading && !isShowingEmptyPage,
            isHovering: isHoveringAddressField,
            isEditing: isEditingAddressField,
            pageTitle: page == nil ? nil : webView.title,
            urlString: page?.absoluteString ?? "",
            host: page?.host
        )
        let field = controls.addressBar.field
        let textChanged = field.stringValue != state.text
        if textChanged {
            field.stringValue = state.text
        }
        // Not editable is not enough: a selectable field still claims an I-beam cursor rect and
        // lets the text be drag-selected. The display state is neither (Safari's arrow cursor);
        // `isEditable = true` turns selectability back on by itself.
        if state.isEditable {
            field.isEditable = true
        } else {
            field.isSelectable = false
        }
        window.invalidateCursorRects(for: field)
        // Leading-aligned in both states — no `.center` while displaying. The display layout
        // already sizes the field to its text, so centering the *field* centers the text; and a
        // fixed alignment is what lets the text ride along with the field's frame when the bar
        // animates between states instead of jumping to the other edge first.
        // Before `isEditing`, so the slide it animates already accounts for both: refresh makes
        // way while editing (`showsEmbeddedRefreshIcon`), and a page pins its icon.
        controls.addressBar.isRefreshVisible = AddressFieldPresenter.showsEmbeddedRefreshIcon(
            hasNavigatedAtLeastOnce: isShowingPage, isEditing: state.isEditable)
        controls.addressBar.trailingAction = AddressFieldPresenter.embeddedTrailingAction(
            isLoading: isLoading && !isShowingEmptyPage)
        controls.addressBar.pinsIcon = isShowingPage
        controls.addressBar.isEditing = state.isEditable
        // The display layout hugs the text, so a new title/URL moves it.
        if textChanged {
            controls.addressBar.needsLayout = true
        }
    }

    /// Brings the address bar's leading glyph in step with what is on screen
    /// (`DesignTokens.addressFieldLeadingIcon` — the favicon or a globe on a page, the magnifying
    /// glass on the Empty Page). Refresh's visibility also depends on editing, so it is decided
    /// in `updateAddressFieldDisplay` instead.
    private func updateAddressFieldIcons() {
        let leadingState = DesignTokens.addressFieldLeadingIcon(
            hasLoadedPage: isShowingPage, hasSiteIcon: siteIcon != nil)
        if leadingState == .siteIcon, let siteIcon {
            controls.addressBar.leadingIconView.image = siteIcon
        } else {
            guard let symbolName = leadingState.symbolName else { return }
            controls.addressBar.leadingIconView.image = ToolbarStyle.symbolImage(
                symbolName, accessibilityDescription: leadingState.accessibilityLabel,
                pointSize: ToolbarStyle.GlyphSize.addressFieldLeading)
        }
        controls.addressBar.leadingIconView.setAccessibilityLabel(leadingState.accessibilityLabel)
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
        controls.addressBar.addTrackingArea(trackingArea)
    }

    /// Flips the field into its editable state (story #4), ahead of `activateAddressField`
    /// handing it focus — so the one click both reveals the URL and makes it typeable.
    ///
    /// A load in flight is no longer a reason to refuse: `AddressFieldPresenter` now ranks editing
    /// above loading, so a heavy page can't leave the address bar unclickable while it finishes.
    /// What that used to protect against is handled by the deferred check instead — if AppKit ends
    /// up not granting the field an editor, there is no blur notification coming to clear the flag,
    /// and the bar would sit in its editable-URL state indefinitely.
    private func beginEditingAddressField() {
        guard !isEditingAddressField else { return }
        isEditingAddressField = true
        updateAddressFieldDisplay()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditingAddressField,
                self.controls.addressBar.field.currentEditor() == nil
            else { return }
            self.isEditingAddressField = false
            self.updateAddressFieldDisplay()
        }
    }

    /// A click anywhere on the capsule while nobody is editing — the text, its rim, the site icon
    /// (`AddressField` forwards its own clicks here). Enters editing, then hands the field focus
    /// with its whole address selected, the way Safari's bar behaves when clicked anywhere.
    private func activateAddressField() {
        beginEditingAddressField()
        window.makeFirstResponder(controls.addressBar.field)
    }

    /// 打开位置… (⌘L, #61): the click path above, plus an explicit select-all — so a second ⌘L
    /// while the user is already mid-edit reselects the whole address instead of keeping the caret
    /// wherever it was.
    func focusAddressField() {
        activateAddressField()
        controls.addressBar.field.currentEditor()?.selectAll(nil)
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
        guard let field = obj.object as? NSTextField, field === controls.addressBar.field else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.controls.addressBar.field.currentEditor() == nil else { return }
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
        setShowingEmptyPage(false)
    }

    /// Switches the content area to the Empty Page's native content, hiding `webView` — the
    /// counterpart to `loadURL`. Also resets `errorPageHostingView` like every other transition
    /// between this shared container's three layers does, even though no caller reaches this
    /// while an error page is showing today — leaving it out here was a real inconsistency the
    /// next caller could trip over (code review finding, #38 review).
    func showEmptyPage() {
        defer { updateTitlebarBackdrop() }
        if !hasNavigatedAtLeastOnce {
            startedOnEmptyPage = true
        }
        webView.isHidden = true
        errorPageHostingView.isHidden = true
        emptyPageHostingView.isHidden = false
        setShowingEmptyPage(true)
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
        // A failure that lands after going back onto the Empty Page belongs to the page left
        // behind: forward shows it, but it must not cover the Empty Page now.
        if isShowingEmptyPage {
            emptyPageCoveredErrorPage = true
        } else {
            errorPageHostingView.isHidden = false
        }
    }

    func setNavigationFinishedHandler(_ handler: @escaping () -> Void) {
        navigationFinishedHandler = handler
    }

    func setNavigationFailedHandler(_ handler: @escaping (String) -> Void) {
        navigationFailedHandler = handler
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A retry (which reloads `webView` directly, bypassing `loadURL`) needs the error page
        // cleared here — `loadURL` only covers navigations that went through it. Not while the
        // Empty Page is up, though: a load that finishes after going back onto it must not pull
        // the page over it.
        if isShowingEmptyPage {
            emptyPageCoveredErrorPage = false
        } else {
            errorPageHostingView.isHidden = true
            webView.isHidden = false
        }
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
            layoutToolbarItems()
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
        guard control === controls.addressBar.field, commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        guard let url = Self.resolveURL(from: controls.addressBar.field.stringValue) else { return true }
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
        // `visibilityPriority` is AppKit's own responsive-collapse mechanism (ADR-0011): as the
        // window narrows, the toolbar sweeps its lowest-priority items into the "更多工具栏项"
        // overflow popup first. Nothing is ever left there: `layoutToolbarItems` hides Ghost Mode
        // (`.standard`, the first candidate) before AppKit would move it, and the window's
        // minimum width keeps the navigation control and the address field (`.high`) in place. `label` is what an item
        // is called once it lands in the overflow menu — it stays invisible in the toolbar
        // itself, which runs in `.iconOnly` display mode.
        switch itemIdentifier {
        case Self.navigationItemID:
            item.view = controls.navigationControl
            item.label = "后退/前进"
            item.visibilityPriority = .high
        case Self.addressItemID:
            item.view = controls.addressBar
            item.label = "地址"
            item.visibilityPriority = .high
        case Self.ghostModeItemID:
            // A stock image+action item, not a custom view (#44) — deliberately, since this
            // button never has an active state to reflect: Ghost Mode hides the whole toolbar the
            // moment it's entered, so nobody could ever see it drawn "on".
            item.image = ToolbarStyle.ghostImage(
                pointSize: ToolbarStyle.GlyphSize.toolbarItem, accessibilityDescription: "进入幽灵模式")
            item.target = self
            item.action = #selector(handleGhostModeToggleRequested)
            item.toolTip = "进入幽灵模式"
            item.label = "幽灵模式"
            item.visibilityPriority = .standard
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

        let emptyPageHostingView: NSHostingView<EmptyPageView> = NativePageHostingView(
            rootView: EmptyPageView(topInset: DesignTokens.Layout.normalModeToolbarRowHeight))
        emptyPageHostingView.translatesAutoresizingMaskIntoConstraints = false
        emptyPageHostingView.isHidden = true

        // The error page (#38) starts with placeholder content — `showErrorPage(message:)`
        // replaces `rootView` with the real failure before ever making this visible.
        let errorPageHostingView: NSHostingView<ErrorPageView> = NativePageHostingView(
            rootView: ErrorPageView(failedURL: "", message: "", onRetry: {}))
        errorPageHostingView.translatesAutoresizingMaskIntoConstraints = false
        errorPageHostingView.isHidden = true

        // Neither native page lays itself out against the window's safe area: a safe area follows
        // the window's chrome, and Ghost Mode removes the titlebar — the inset dropped to 0, the
        // page re-laid itself out across the whole container (whose top 52pt hang off the window
        // in Ghost Mode) and its content jumped up. Instead the toolbar strip's height is given to
        // each explicitly, as fixed as the web view's `obscuredContentInsets`: the Empty Page runs
        // full-bleed under the floating toolbar and is told the height (`EmptyPageView.topInset`);
        // the error page, like a loaded page, starts below the strip (`nativePageTopConstraints`).
        emptyPageHostingView.safeAreaRegions = []
        errorPageHostingView.safeAreaRegions = []

        // `webView`, `emptyPageHostingView` (#16), and `errorPageHostingView` (#38) share this
        // container, exactly one visible at a time (see `loadURL`/`showEmptyPage`/`showErrorPage`).
        // The web view and the Empty Page fill it completely; the error page starts below the strip.
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(webView)
        contentContainer.addSubview(emptyPageHostingView)
        contentContainer.addSubview(errorPageHostingView)
        let nativePageTopConstraints = [
            errorPageHostingView.topAnchor.constraint(
                equalTo: contentContainer.topAnchor, constant: DesignTokens.Layout.normalModeToolbarRowHeight),
        ]
        NSLayoutConstraint.activate(nativePageTopConstraints + [
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
            nativePageTopConstraints: nativePageTopConstraints,
            contentContainerTopConstraint: contentContainerTopConstraint
        )

        let toolbar = NSToolbar(identifier: "MochiNormalModeToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.delegate = handle
        toolbar.centeredItemIdentifiers = [AppKitWidgetWindowHandle.addressItemID]
        window.toolbar = toolbar
        handle.normalModeToolbar = toolbar

        return handle
    }

    /// Builds the Normal Mode toolbar's controls (ADR-0009/ADR-0011) — the Smart Address Field's
    /// `AddressBarView` (capsule, site icon, text and embedded refresh affordance as siblings) and
    /// a native segmented control for back/forward — all hosted as `NSToolbarItem` views by
    /// `AppKitWidgetWindowHandle`'s `NSToolbarDelegate` conformance. Settings is not here: it is
    /// a stock image+action item built in that delegate.
    private func makeToolbarControls() -> ToolbarControls {
        // Refresh lives inside the capsule (ADR-0011) rather than as a standalone `NSToolbarItem`.
        // Visibility (hidden until the first real navigation) is owned by `updateAddressFieldIcons`.
        // Its glyph and tooltip swap to stop while loading (#60, `AddressBarView.trailingAction`).
        let initialAction = AddressFieldPresenter.EmbeddedTrailingAction.reload
        let refreshButton = embeddedButton(
            image: ToolbarStyle.symbolImage(
                initialAction.symbolName, accessibilityDescription: initialAction.toolTip,
                pointSize: ToolbarStyle.GlyphSize.addressFieldEmbedded))
        refreshButton.toolTip = initialAction.toolTip
        // Stable handle for UI automation and accessibility tooling (Safari's own is `ReloadButton`).
        let refreshID = NSUserInterfaceItemIdentifier("com.mochi.addressBar.reload")
        refreshButton.identifier = refreshID
        refreshButton.setAccessibilityIdentifier(refreshID.rawValue)
        let addressBar = AddressBarView(refreshButton: refreshButton)
        addressBar.field.placeholderString = "输入网址"
        // The leading site icon: the page's favicon, or a symbol standing in for it
        // (`updateAddressFieldIcons` owns which).
        addressBar.leadingIconView.image = ToolbarStyle.symbolImage(
            DesignTokens.AddressFieldLeadingIcon.search.symbolName!,
            accessibilityDescription: DesignTokens.AddressFieldLeadingIcon.search.accessibilityLabel,
            pointSize: ToolbarStyle.GlyphSize.addressFieldLeading)

        // Bounded elastic width (ADR-0011), replacing the earlier "fill every point left over
        // between the neighbouring items": low hugging still lets `NSToolbarItem` grow the bar
        // into spare width — per the `NSToolbarItem.minSize`/`maxSize` SDK header, the toolbar
        // "automatically measure[s] the size of the view using constraints" rather than consulting
        // those (deprecated) properties — but the required upper bound stops that growth at
        // `addressFieldMaxWidth`. Both bounds are required, so the layout system's fitting-size
        // measurement stays inside them; the trap #23 fell into was a huge *low-priority*
        // `width == 10_000` constraint with no upper bound, which became the fitting size itself,
        // so the toolbar decided the item could never fit and swept it straight into the overflow
        // menu instead of sizing it down to the required minimum. The capsule's bounds are padded
        // by the focus-ring inset on every side, same as when the field itself was the capsule.
        let ringInset = DesignTokens.Layout.addressFieldFocusRingInset
        addressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let addressBarMaxWidth = addressBar.widthAnchor.constraint(
            lessThanOrEqualToConstant: DesignTokens.Layout.addressFieldMaxWidth + ringInset * 2)
        NSLayoutConstraint.activate([
            addressBar.widthAnchor.constraint(
                greaterThanOrEqualToConstant: DesignTokens.Layout.addressFieldMinWidth + ringInset * 2),
            addressBarMaxWidth,
            addressBar.heightAnchor.constraint(
                equalToConstant: DesignTokens.Layout.addressFieldHeight + ringInset * 2),
        ])

        return ToolbarControls(
            navigationControl: makeNavigationControl(),
            addressBar: addressBar,
            addressBarMaxWidth: addressBarMaxWidth
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

    /// A borderless icon button for inside the address bar's capsule, which frames its children
    /// by hand (`AddressBarView.layout()`) — hence no size constraints here.
    private func embeddedButton(image: NSImage) -> NSButton {
        let button = HoverIconButton(image: image, target: nil, action: nil)
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = ToolbarStyle.iconTint()
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

    public func stopLoading(in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.stopLoading()
    }

    public func navigationState(of window: WidgetWindowHandle) -> NavigationState {
        handle(for: window)?.navigationState ?? NavigationState()
    }

    public func goBack(in window: WidgetWindowHandle) {
        handle(for: window)?.goBack()
    }

    public func goForward(in window: WidgetWindowHandle) {
        handle(for: window)?.goForward()
    }

    public func focusAddressBar(in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.focusAddressField()
    }

    public func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setURLSubmittedHandler(handler)
    }

    public func setPinned(_ pinned: Bool, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.setPinned(pinned)
    }

    public func onGhostModeToggleRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setGhostModeToggleRequestedHandler(handler)
    }

    public func deactivateApp() {
        NSApp.deactivate()
    }

    public func activateApp() {
        NSApp.activate()
    }

    public func injectScript(_ source: String, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.injectScript(source)
    }

    public func onEmptyPageVisibilityChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setEmptyPageVisibilityChangedHandler(handler)
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
