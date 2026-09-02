import AppKit
import Foundation
import WebKit

private let toolbarHeight: CGFloat = 44

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
/// Icons are real SF Symbols for now (all of back/forward/refresh/pin exist as system symbols);
/// swap for the bespoke vector icon set + `DesignTokens` colors once #17 lands.
final class AppKitWidgetWindowHandle: NSObject, WidgetWindowHandle, NSWindowDelegate, NSTextFieldDelegate {
    let window: NSWindow
    let webView: WKWebView
    private let toolbarGlass: NSGlassEffectView
    private let controls: ToolbarControls
    private var willCloseHandler: (() -> Void)?
    private var urlSubmittedHandler: ((URL) -> Void)?
    private var isPinned = false
    private var navigationObservations: [NSKeyValueObservation] = []

    fileprivate init(window: NSWindow, webView: WKWebView, toolbarGlass: NSGlassEffectView, controls: ToolbarControls) {
        self.window = window
        self.webView = webView
        self.toolbarGlass = toolbarGlass
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
        observeNavigationState()
    }

    private func observeNavigationState() {
        controls.backButton.isEnabled = webView.canGoBack
        controls.forwardButton.isEnabled = webView.canGoForward
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                self?.controls.backButton.isEnabled = change.newValue ?? false
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                self?.controls.forwardButton.isEnabled = change.newValue ?? false
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, change in
                if let url = change.newValue ?? nil {
                    self?.controls.addressField.stringValue = url.absoluteString
                }
            },
        ]
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
        controls.pinButton.contentTintColor = isPinned ? .controlAccentColor : nil
    }

    func setWillCloseHandler(_ handler: @escaping () -> Void) {
        willCloseHandler = handler
    }

    func setURLSubmittedHandler(_ handler: @escaping (URL) -> Void) {
        urlSubmittedHandler = handler
    }

    func setToolbarVisible(_ visible: Bool) {
        toolbarGlass.isHidden = !visible
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
        let toolbarGlass = makeToolbarGlass(containing: controls)

        let rootStack = NSStackView(views: [toolbarGlass, webView])
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

        return AppKitWidgetWindowHandle(window: window, webView: webView, toolbarGlass: toolbarGlass, controls: controls)
    }

    private func makeToolbarControls() -> ToolbarControls {
        let addressField = NSTextField()
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.bezelStyle = .roundedBezel
        addressField.placeholderString = "输入网址"
        addressField.lineBreakMode = .byTruncatingTail
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return ToolbarControls(
            backButton: toolbarButton(symbolName: "chevron.left", accessibilityDescription: "后退"),
            forwardButton: toolbarButton(symbolName: "chevron.right", accessibilityDescription: "前进"),
            refreshButton: toolbarButton(symbolName: "arrow.clockwise", accessibilityDescription: "刷新"),
            pinButton: toolbarButton(symbolName: "pin", accessibilityDescription: "置顶"),
            addressField: addressField
        )
    }

    private func makeToolbarGlass(containing controls: ToolbarControls) -> NSGlassEffectView {
        let buttonsStack = NSStackView(views: [
            controls.backButton, controls.forwardButton, controls.refreshButton, controls.addressField, controls.pinButton,
        ])
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let toolbarGlass = NSGlassEffectView()
        toolbarGlass.translatesAutoresizingMaskIntoConstraints = false
        toolbarGlass.cornerRadius = 12
        toolbarGlass.contentView = buttonsStack
        toolbarGlass.heightAnchor.constraint(equalToConstant: toolbarHeight).isActive = true
        return toolbarGlass
    }

    private func toolbarButton(symbolName: String, accessibilityDescription: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) ?? NSImage(), target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
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
