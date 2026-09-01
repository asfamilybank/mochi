import Foundation

public protocol WidgetWindowHandle {}

public protocol PlatformOps: AnyObject {
    func createWidgetWindow() -> WidgetWindowHandle
    func loadURL(_ url: URL, in window: WidgetWindowHandle)
    func showWindow(_ window: WidgetWindowHandle)
}
