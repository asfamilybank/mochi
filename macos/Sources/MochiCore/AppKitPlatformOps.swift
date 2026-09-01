import AppKit
import Foundation
import WebKit

public final class AppKitWidgetWindowHandle: WidgetWindowHandle {
    let window: NSWindow
    let webView: WKWebView

    init(window: NSWindow, webView: WKWebView) {
        self.window = window
        self.webView = webView
    }
}

public final class AppKitPlatformOps: PlatformOps {
    public init() {}

    public func createWidgetWindow() -> WidgetWindowHandle {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mochi"
        window.contentView = webView
        return AppKitWidgetWindowHandle(window: window, webView: webView)
    }

    public func loadURL(_ url: URL, in window: WidgetWindowHandle) {
        guard let handle = window as? AppKitWidgetWindowHandle else { return }
        handle.webView.load(URLRequest(url: url))
    }

    public func showWindow(_ window: WidgetWindowHandle) {
        guard let handle = window as? AppKitWidgetWindowHandle else { return }
        handle.window.makeKeyAndOrderFront(nil)
    }
}
