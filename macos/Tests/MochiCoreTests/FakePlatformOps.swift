import Foundation

@testable import MochiCore

final class FakeWidgetWindowHandle: WidgetWindowHandle {
    let id: Int
    init(id: Int) { self.id = id }
}

final class FakePlatformOps: PlatformOps {
    private(set) var createdFrames: [WindowFrame] = []
    private(set) var loadedURLs: [(url: URL, windowID: Int)] = []
    private(set) var emptyPageShownWindowIDs: [Int] = []
    private(set) var shownWindowIDs: [Int] = []
    private(set) var appliedZooms: [(zoom: Double, windowID: Int)] = []
    private(set) var toolbarVisibilityChanges: [(visible: Bool, windowID: Int)] = []
    private(set) var pinnedChanges: [(pinned: Bool, windowID: Int)] = []
    private(set) var injectedScripts: [(source: String, windowID: Int)] = []
    private(set) var nativeChromeVisibilityChanges: [(visible: Bool, windowID: Int)] = []
    private(set) var contentOpacityChanges: [(opacity: Double, windowID: Int)] = []
    private(set) var mousePassthroughChanges: [(enabled: Bool, windowID: Int)] = []
    private(set) var windowHiddenChanges: [(hidden: Bool, windowID: Int)] = []
    private(set) var registeredHotkeys: [Hotkey] = []
    private(set) var presentedAlerts: [(title: String, message: String)] = []
    private(set) var snapThresholdChanges: [(threshold: Double, windowID: Int)] = []
    private(set) var trayMenuItems: [TrayMenuItem] = []
    private(set) var terminateAppCallCount = 0
    private(set) var reloadedWindowIDs: [Int] = []
    private(set) var accessibilityPermissionRequestCount = 0
    private(set) var forwardedKeystrokes: [Hotkey] = []
    private(set) var windowTitleChanges: [(title: String, windowID: Int)] = []
    private var willCloseHandlers: [Int: () -> Void] = [:]
    private var urlSubmittedHandlers: [Int: (URL) -> Void] = [:]
    private var settingsRequestedHandlers: [Int: () -> Void] = [:]
    private var navigationFinishedHandlers: [Int: () -> Void] = [:]
    private var mouseEnteredHandlers: [Int: () -> Void] = [:]
    private var pageTitleChangedHandlers: [Int: (String?) -> Void] = [:]
    private var loadingStateChangedHandlers: [Int: (Bool) -> Void] = [:]
    private var loadingProgressChangedHandlers: [Int: (Double) -> Void] = [:]
    private var hotkeyHandlers: [() -> Void] = []

    var stubbedHotkeyRegistrationSucceeds = true
    var stubbedAccessibilityTrusted = true

    var stubbedScreens: [CGRect] = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    var stubbedCapturedWindowState = WindowState(
        frame: WindowFrame(x: 0, y: 0, width: 1024, height: 768), zoom: 1.0)

    func createWidgetWindow(initialFrame: WindowFrame) -> WidgetWindowHandle {
        createdFrames.append(initialFrame)
        return FakeWidgetWindowHandle(id: createdFrames.count)
    }

    func loadURL(_ url: URL, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        loadedURLs.append((url, handle.id))
    }

    func showEmptyPageContent(in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        emptyPageShownWindowIDs.append(handle.id)
    }

    func showWindow(_ window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        shownWindowIDs.append(handle.id)
    }

    func applyZoom(_ zoom: Double, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        appliedZooms.append((zoom, handle.id))
    }

    func captureWindowState(of window: WidgetWindowHandle) -> WindowState {
        stubbedCapturedWindowState
    }

    func onWindowWillClose(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        willCloseHandlers[handle.id] = handler
    }

    func visibleScreens() -> [CGRect] {
        stubbedScreens
    }

    func setToolbarVisible(_ visible: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        toolbarVisibilityChanges.append((visible, handle.id))
    }

    func onURLSubmitted(_ window: WidgetWindowHandle, perform handler: @escaping (URL) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        urlSubmittedHandlers[handle.id] = handler
    }

    func simulateWindowWillClose(windowID: Int = 1) {
        willCloseHandlers[windowID]?()
    }

    func simulateURLSubmitted(_ url: URL, windowID: Int = 1) {
        urlSubmittedHandlers[windowID]?(url)
    }

    func setPinned(_ pinned: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        pinnedChanges.append((pinned, handle.id))
    }

    func onSettingsRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        settingsRequestedHandlers[handle.id] = handler
    }

    func simulateSettingsRequested(windowID: Int = 1) {
        settingsRequestedHandlers[windowID]?()
    }

    func injectScript(_ source: String, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        injectedScripts.append((source, handle.id))
    }

    func onNavigationFinished(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        navigationFinishedHandlers[handle.id] = handler
    }

    func simulateNavigationFinished(windowID: Int = 1) {
        navigationFinishedHandlers[windowID]?()
    }

    func setNativeChromeVisible(_ visible: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        nativeChromeVisibilityChanges.append((visible, handle.id))
    }

    func setContentOpacity(_ opacity: Double, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        contentOpacityChanges.append((opacity, handle.id))
    }

    func setMousePassthrough(_ enabled: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        mousePassthroughChanges.append((enabled, handle.id))
    }

    func setWindowHidden(_ hidden: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        windowHiddenChanges.append((hidden, handle.id))
    }

    func onMouseEntered(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        mouseEnteredHandlers[handle.id] = handler
    }

    func simulateMouseEntered(windowID: Int = 1) {
        mouseEnteredHandlers[windowID]?()
    }

    @discardableResult
    func registerGlobalHotkey(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool {
        registeredHotkeys.append(hotkey)
        guard stubbedHotkeyRegistrationSucceeds else { return false }
        hotkeyHandlers.append(handler)
        return true
    }

    func simulateHotkeyPressed(at index: Int = 0) {
        hotkeyHandlers[index]()
    }

    /// Looks up the handler by matching the hotkey itself rather than a positional index —
    /// insulates tests from `Orchestrator`'s internal hotkey-registration order. Only correct
    /// when every registration up to and including a match succeeded (true whenever
    /// `stubbedHotkeyRegistrationSucceeds` is left at its default), since `hotkeyHandlers` only
    /// contains successful registrations while `registeredHotkeys` contains every attempt.
    func simulateHotkeyPressed(_ hotkey: Hotkey) {
        guard let index = registeredHotkeys.firstIndex(of: hotkey) else { return }
        hotkeyHandlers[index]()
    }

    func presentAlert(title: String, message: String) {
        presentedAlerts.append((title, message))
    }

    func setSnapThreshold(_ threshold: Double, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        snapThresholdChanges.append((threshold, handle.id))
    }

    func createTrayIcon(items: [TrayMenuItem]) {
        trayMenuItems = items
    }

    func terminateApp() {
        terminateAppCallCount += 1
    }

    func reloadPage(in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        reloadedWindowIDs.append(handle.id)
    }

    func isAccessibilityTrusted() -> Bool {
        stubbedAccessibilityTrusted
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionRequestCount += 1
    }

    func forwardKeystroke(_ keystroke: Hotkey) {
        forwardedKeystrokes.append(keystroke)
    }

    func onPageTitleChanged(_ window: WidgetWindowHandle, perform handler: @escaping (String?) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        pageTitleChangedHandlers[handle.id] = handler
    }

    func simulatePageTitleChanged(_ title: String?, windowID: Int = 1) {
        pageTitleChangedHandlers[windowID]?(title)
    }

    func onLoadingStateChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        loadingStateChangedHandlers[handle.id] = handler
    }

    func simulateLoadingStateChanged(_ isLoading: Bool, windowID: Int = 1) {
        loadingStateChangedHandlers[windowID]?(isLoading)
    }

    func onLoadingProgressChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Double) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        loadingProgressChangedHandlers[handle.id] = handler
    }

    func simulateLoadingProgressChanged(_ progress: Double, windowID: Int = 1) {
        loadingProgressChangedHandlers[windowID]?(progress)
    }

    func setWindowTitle(_ title: String, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        windowTitleChanges.append((title, handle.id))
    }
}
