import Foundation

public protocol WidgetWindowHandle {}

public protocol PlatformOps: AnyObject {
    func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle
    func loadURL(_ url: URL, in window: WidgetWindowHandle)
    func showWindow(_ window: WidgetWindowHandle)
    func applyZoom(_ zoom: Double, in window: WidgetWindowHandle)
    func captureWindowState(of window: WidgetWindowHandle) -> WindowState
    func onWindowWillClose(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void)

    /// The visible frame of every connected screen. Index 0 is always the primary
    /// (menu-bar) screen — matches `NSScreen.screens`' documented ordering.
    func visibleScreens() -> [CGRect]

    func setToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle)

    /// Registers a handler invoked when the user manually navigates via the toolbar's
    /// address bar (as opposed to a programmatic `loadURL` call).
    func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void)
}
