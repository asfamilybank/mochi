import AppKit
import CoreGraphics
import Foundation
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

    static func fieldFill() -> NSColor {
        dynamicColor(light: DesignTokens.glassPalette(dark: false).fieldFill, dark: DesignTokens.glassPalette(dark: true).fieldFill)
    }

    static func fieldText() -> NSColor {
        dynamicColor(light: DesignTokens.glassPalette(dark: false).fieldText, dark: DesignTokens.glassPalette(dark: true).fieldText)
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

/// The interactive controls hosted inside the Normal Mode toolbar glass. Bundled together because
/// they're always constructed, wired, and handed off as one unit.
fileprivate struct ToolbarControls {
    let backButton: NSButton
    let forwardButton: NSButton
    let refreshButton: NSButton
    let pinButton: NSButton
    let addressField: NSTextField
}

/// Custom-drawn Normal Mode toolbar: back/forward/refresh + an editable address bar + a Pin
/// toggle, embedded in a real Liquid Glass material (`NSGlassEffectView`, macOS 26+; see
/// ADR-0008). Sits above the WKWebView in its own row — never overlapping page content — inside
/// a vertical NSStackView, which is also what lets `setToolbarVisible` collapse it later for
/// Ghost Mode (#8) without any extra layout bookkeeping here.
///
/// Colors, corner radii, spacing, and the bespoke vector icon set all come from `DesignTokens`/
/// `DesignIcon` (#17) — nothing here writes its own numbers.
final class AppKitWidgetWindowHandle: NSObject, WidgetWindowHandle, NSWindowDelegate, NSTextFieldDelegate {
    let window: NSWindow
    let webView: WKWebView
    private let toolbarContainer: NSView
    private let controls: ToolbarControls
    private var willCloseHandler: (() -> Void)?
    private var urlSubmittedHandler: ((URL) -> Void)?
    private var isPinned = false
    private var navigationObservations: [NSKeyValueObservation] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var accentColorObserver: NSObjectProtocol?

    fileprivate init(window: NSWindow, webView: WKWebView, toolbarContainer: NSView, controls: ToolbarControls) {
        self.window = window
        self.webView = webView
        self.toolbarContainer = toolbarContainer
        self.controls = controls
        super.init()
        window.delegate = self
        controls.addressField.delegate = self
        controls.backButton.target = self
        controls.backButton.action = #selector(goBack)
        controls.forwardButton.target = self
        controls.forwardButton.action = #selector(goForward)
        controls.refreshButton.target = self
        controls.refreshButton.action = #selector(reload)
        controls.pinButton.target = self
        controls.pinButton.action = #selector(togglePinned)
        controls.pinButton.wantsLayer = true
        controls.pinButton.layer?.cornerRadius = DesignTokens.Layout.toolbarButtonDiameter / 2
        observeNavigationState()
        updatePinButtonAppearance()
        // The Pin capsule's tint is baked into CALayer colors (not a dynamic NSColor), so unlike
        // everywhere else in this file it needs to be re-applied whenever the system accent color
        // or the window's light/dark appearance changes, instead of re-resolving for free at draw time.
        appearanceObservation = window.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.updatePinButtonAppearance()
        }
        accentColorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updatePinButtonAppearance()
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
                if let url = change.newValue ?? nil {
                    self?.controls.addressField.stringValue = url.absoluteString
                }
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

    @objc private func reload() {
        webView.reload()
    }

    @objc private func togglePinned() {
        isPinned.toggle()
        window.level = isPinned ? .floating : .normal
        updatePinButtonAppearance()
    }

    /// The Pin toggle's active state: a tinted glass background + border + icon in the
    /// system accent color, matching macOS's own selected-state glass tinting (design-language.md,
    /// "工具栏与工具栏"). Inactive state falls back to the plain toolbar icon tint.
    private func updatePinButtonAppearance() {
        guard let layer = controls.pinButton.layer else { return }
        if isPinned {
            let tint = DesignTokens.accentTint(DesignTokens.resolveSystemAccent())
            layer.backgroundColor = NSColor(rgba: tint.background).cgColor
            layer.borderWidth = 1
            layer.borderColor = NSColor(rgba: tint.border).cgColor
            controls.pinButton.contentTintColor = NSColor(rgba: tint.icon)
        } else {
            layer.backgroundColor = nil
            layer.borderWidth = 0
            controls.pinButton.contentTintColor = ToolbarStyle.iconTint()
        }
    }

    func setWillCloseHandler(_ handler: @escaping () -> Void) {
        willCloseHandler = handler
    }

    func setURLSubmittedHandler(_ handler: @escaping (URL) -> Void) {
        urlSubmittedHandler = handler
    }

    func setToolbarVisible(_ visible: Bool) {
        toolbarContainer.isHidden = !visible
    }

    func windowWillClose(_ notification: Notification) {
        willCloseHandler?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === controls.addressField, commandSelector == #selector(NSResponder.insertNewline(_:)) else {
            return false
        }
        guard let url = Self.resolveURL(from: controls.addressField.stringValue) else { return true }
        urlSubmittedHandler?(url)
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
}

public final class AppKitPlatformOps: PlatformOps {
    public init() {}

    public func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle {
        let rect = NSRect(x: initialFrame.x, y: initialFrame.y, width: initialFrame.width, height: initialFrame.height)
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false

        let controls = makeToolbarControls()
        let toolbarContainer = makeToolbarRow(containing: controls)

        let rootStack = NSStackView(views: [toolbarContainer, webView])
        rootStack.orientation = .vertical
        rootStack.spacing = 0
        rootStack.distribution = .fill
        rootStack.alignment = .width

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mochi"
        window.contentView = rootStack

        return AppKitWidgetWindowHandle(window: window, webView: webView, toolbarContainer: toolbarContainer, controls: controls)
    }

    private func makeToolbarControls() -> ToolbarControls {
        let addressField = NSTextField()
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.isBezeled = false
        addressField.isBordered = false
        addressField.drawsBackground = true
        addressField.backgroundColor = ToolbarStyle.fieldFill()
        addressField.textColor = ToolbarStyle.fieldText()
        addressField.wantsLayer = true
        addressField.layer?.cornerRadius = DesignTokens.Layout.addressFieldCornerRadius
        addressField.layer?.masksToBounds = true
        addressField.placeholderString = "输入网址"
        addressField.lineBreakMode = .byTruncatingTail
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addressField.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.addressFieldHeight).isActive = true

        return ToolbarControls(
            backButton: toolbarButton(icon: .chevronLeft, accessibilityDescription: "后退"),
            forwardButton: toolbarButton(icon: .chevronRight, accessibilityDescription: "前进"),
            refreshButton: toolbarButton(icon: .refresh, accessibilityDescription: "刷新"),
            pinButton: toolbarButton(icon: .pin, accessibilityDescription: "置顶"),
            addressField: addressField
        )
    }

    /// The Liquid Glass toolbar capsule, floating with the design canvas's outer margin inside
    /// its row — the row itself (not just the glass) collapses when `setToolbarVisible(false)`.
    private func makeToolbarRow(containing controls: ToolbarControls) -> NSView {
        let buttonsStack = NSStackView(views: [
            controls.backButton, controls.forwardButton, controls.refreshButton, controls.addressField, controls.pinButton,
        ])
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = DesignTokens.Layout.toolbarButtonSpacing
        buttonsStack.edgeInsets = NSEdgeInsets(
            top: DesignTokens.Layout.toolbarInnerPaddingVertical,
            left: DesignTokens.Layout.toolbarInnerPaddingHorizontal,
            bottom: DesignTokens.Layout.toolbarInnerPaddingVertical,
            right: DesignTokens.Layout.toolbarInnerPaddingHorizontal
        )

        let toolbarGlass = NSGlassEffectView()
        toolbarGlass.translatesAutoresizingMaskIntoConstraints = false
        toolbarGlass.cornerRadius = DesignTokens.Layout.toolbarCapsuleCornerRadius
        toolbarGlass.tintColor = ToolbarStyle.glassTint()
        toolbarGlass.contentView = buttonsStack
        toolbarGlass.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.toolbarCapsuleHeight).isActive = true

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(toolbarGlass)
        NSLayoutConstraint.activate([
            toolbarGlass.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: DesignTokens.Layout.toolbarOuterPaddingHorizontal),
            toolbarGlass.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -DesignTokens.Layout.toolbarOuterPaddingHorizontal),
            toolbarGlass.topAnchor.constraint(equalTo: row.topAnchor, constant: DesignTokens.Layout.toolbarOuterPaddingVertical),
            toolbarGlass.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -DesignTokens.Layout.toolbarOuterPaddingVertical),
        ])
        return row
    }

    private func toolbarButton(icon: DesignIcon, accessibilityDescription: String) -> NSButton {
        let image = ToolbarStyle.templateImage(for: icon, accessibilityDescription: accessibilityDescription)
        let button = NSButton(image: image, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = ToolbarStyle.iconTint()
        button.widthAnchor.constraint(equalToConstant: DesignTokens.Layout.toolbarButtonDiameter).isActive = true
        button.heightAnchor.constraint(equalToConstant: DesignTokens.Layout.toolbarButtonDiameter).isActive = true
        return button
    }

    public func loadURL(_ url: URL, in window: WidgetWindowHandle) {
        guard let handle = handle(for: window) else { return }
        handle.webView.load(URLRequest(url: url))
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

    public func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void) {
        guard let handle = handle(for: window) else { return }
        handle.setURLSubmittedHandler(handler)
    }

    private func handle(for window: WidgetWindowHandle) -> AppKitWidgetWindowHandle? {
        window as? AppKitWidgetWindowHandle
    }
}
