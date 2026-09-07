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
    private(set) var registeredHotkeys: [Hotkey] = []
    private(set) var unregisteredHotkeys: [Hotkey] = []
    /// The interleaved register/unregister sequence — for assertions where the *order* of the two
    /// is the point (release the old combo before claiming the new one, #45/#46).
    private(set) var hotkeyCallOrder: [HotkeyCall] = []

    enum HotkeyCall: Equatable {
        case register(Hotkey)
        case unregister(Hotkey)
    }
    private(set) var presentedAlerts: [(title: String, message: String)] = []
    private(set) var snapEnabledChanges: [(enabled: Bool, windowID: Int)] = []
    private(set) var trayMenuItems: [TrayMenuItem] = []
    private(set) var createTrayIconCallCount = 0
    private(set) var closedWindowIDs: [Int] = []
    private var reopenRequestedHandler: (() -> Void)?
    private(set) var terminateAppCallCount = 0
    private(set) var reloadedWindowIDs: [Int] = []
    private(set) var accessibilityPermissionRequestCount = 0
    private(set) var forwardedKeystrokes: [Hotkey] = []
    private(set) var windowTitleChanges: [(title: String, windowID: Int)] = []
    private(set) var errorPagesShown: [(message: String, windowID: Int)] = []
    private var willCloseHandlers: [Int: () -> Void] = [:]
    private var urlSubmittedHandlers: [Int: (URL) -> Void] = [:]
    private var settingsRequestedHandlers: [Int: () -> Void] = [:]
    private var navigationFinishedHandlers: [Int: () -> Void] = [:]
    private var navigationFailedHandlers: [Int: (String) -> Void] = [:]
    private var ghostModeToggleRequestedHandlers: [Int: () -> Void] = [:]
    private(set) var deactivateAppCallCount = 0
    private var mouseInsideChangedHandlers: [Int: (Bool) -> Void] = [:]
    private var pageTitleChangedHandlers: [Int: (String?) -> Void] = [:]
    private var loadingStateChangedHandlers: [Int: (Bool) -> Void] = [:]
    private var loadingProgressChangedHandlers: [Int: (Double) -> Void] = [:]
    private var hotkeyHandlers: [Hotkey: () -> Void] = [:]

    var stubbedHotkeyRegistrationSucceeds = true
    /// Combos that fail to register as if another application held them, while everything else
    /// still succeeds — the rollback tests need exactly one combo to fail.
    var hotkeysThatFailToRegister: Set<Hotkey> = []
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

    /// Mirrors `AppKitPlatformOps`: `NSWindow.close()` fires the delegate's `windowWillClose`,
    /// so closing through this call reaches the registered will-close handler the same way the red
    /// close button does.
    func closeWidgetWindow(_ window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        closedWindowIDs.append(handle.id)
        willCloseHandlers[handle.id]?()
    }

    func onReopenRequested(perform handler: @escaping () -> Void) {
        reopenRequestedHandler = handler
    }

    func simulateReopenRequested() {
        reopenRequestedHandler?()
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

    func onGhostModeToggleRequested(_ window: WidgetWindowHandle, perform handler: @escaping () -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        ghostModeToggleRequestedHandlers[handle.id] = handler
    }

    func simulateGhostModeToggleRequested(windowID: Int = 1) {
        ghostModeToggleRequestedHandlers[windowID]?()
    }

    func deactivateApp() {
        deactivateAppCallCount += 1
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

    func onNavigationFailed(_ window: WidgetWindowHandle, perform handler: @escaping (String) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        navigationFailedHandlers[handle.id] = handler
    }

    func simulateNavigationFailed(_ message: String, windowID: Int = 1) {
        navigationFailedHandlers[windowID]?(message)
    }

    func showErrorPageContent(message: String, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        errorPagesShown.append((message, handle.id))
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

    func onMouseInsideChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        mouseInsideChangedHandlers[handle.id] = handler
    }

    func simulateMouseInsideChanged(_ inside: Bool, windowID: Int = 1) {
        mouseInsideChangedHandlers[windowID]?(inside)
    }

    @discardableResult
    func registerGlobalHotkey(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool {
        registeredHotkeys.append(hotkey)
        hotkeyCallOrder.append(.register(hotkey))
        guard stubbedHotkeyRegistrationSucceeds, !hotkeysThatFailToRegister.contains(hotkey) else { return false }
        hotkeyHandlers[hotkey] = handler
        return true
    }

    /// Fires the handler of the first combo ever registered — `Orchestrator` registers the Ghost
    /// Mode toggle first, so this is "press the toggle" for tests that don't care which combo.
    func simulateHotkeyPressed() {
        guard let first = registeredHotkeys.first else { return }
        simulateHotkeyPressed(first)
    }

    /// Fires the handler *currently* registered for `hotkey` — mirrors `GlobalHotkeyRegistry`,
    /// where a later registration of the same combo replaces the earlier handler and an
    /// unregister removes it, so a combo that was released does nothing here either.
    func simulateHotkeyPressed(_ hotkey: Hotkey) {
        hotkeyHandlers[hotkey]?()
    }

    func unregisterGlobalHotkey(_ hotkey: Hotkey) {
        unregisteredHotkeys.append(hotkey)
        hotkeyCallOrder.append(.unregister(hotkey))
        hotkeyHandlers.removeValue(forKey: hotkey)
    }

    func presentAlert(title: String, message: String) {
        presentedAlerts.append((title, message))
    }

    func setSnapEnabled(_ enabled: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        snapEnabledChanges.append((enabled, handle.id))
    }

    func createTrayIcon(items: [TrayMenuItem]) {
        createTrayIconCallCount += 1
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
