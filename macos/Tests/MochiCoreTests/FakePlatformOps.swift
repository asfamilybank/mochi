import Foundation

@testable import MochiCore

final class FakeWidgetWindowHandle: WidgetWindowHandle {
    let id: Int
    init(id: Int) { self.id = id }
}

final class FakePlatformOps: PlatformOps {
    private(set) var createdWindowCount = 0
    private(set) var loadedURLs: [(url: URL, windowID: Int)] = []
    private(set) var shownWindowIDs: [Int] = []

    func createWidgetWindow() -> WidgetWindowHandle {
        createdWindowCount += 1
        return FakeWidgetWindowHandle(id: createdWindowCount)
    }

    func loadURL(_ url: URL, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        loadedURLs.append((url, handle.id))
    }

    func showWindow(_ window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        shownWindowIDs.append(handle.id)
    }
}
