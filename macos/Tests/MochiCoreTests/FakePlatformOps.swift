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
    // #70
    private(set) var createdAutoplayPolicies: [WidgetConfig.AutoplayPolicy] = []
    private(set) var minimumFontSizeChanges: [(size: Int?, windowID: Int)] = []
    private(set) var trayMenuItems: [TrayMenuItem] = []
    private(set) var createTrayIconCallCount = 0
    private(set) var closedWindowIDs: [Int] = []
    private var reopenRequestedHandler: (() -> Void)?
    private(set) var terminateAppCallCount = 0
    private(set) var reloadedWindowIDs: [Int] = []
    private(set) var stoppedLoadingWindowIDs: [Int] = []
    private(set) var accessibilityPermissionRequestCount = 0
    private(set) var forwardedKeystrokes: [Hotkey] = []
    private(set) var forwardedKeystrokeWindowIDs: [Int] = []
    private(set) var windowTitleChanges: [(title: String, windowID: Int)] = []
    private(set) var errorPagesShown: [(message: String, windowID: Int)] = []
    private var willCloseHandlers: [Int: () -> Void] = [:]
    private var urlSubmittedHandlers: [Int: (URL) -> Void] = [:]
    private var navigationFinishedHandlers: [Int: () -> Void] = [:]
    private var navigationFailedHandlers: [Int: (String) -> Void] = [:]
    private var ghostModeToggleRequestedHandlers: [Int: () -> Void] = [:]
    private(set) var deactivateAppCallCount = 0
    private(set) var activateAppCallCount = 0
    private var pageTitleChangedHandlers: [Int: (String?) -> Void] = [:]
    private var emptyPageVisibilityChangedHandlers: [Int: (Bool) -> Void] = [:]
    private var loadingStateChangedHandlers: [Int: (Bool) -> Void] = [:]
    private var loadingProgressChangedHandlers: [Int: (Double) -> Void] = [:]
    private var hotkeyHandlers: [Hotkey: () -> Void] = [:]

    var stubbedHotkeyRegistrationSucceeds = true
    /// Combos that fail to register as if another application held them, while everything else
    /// still succeeds — the rollback tests need exactly one combo to fail.
    var hotkeysThatFailToRegister: Set<Hotkey> = []
    var stubbedAccessibilityTrusted = true
    /// What `navigationState(of:)` answers — the AppKit side's effective back/forward/loading.
    var stubbedNavigationState = NavigationState()

    var stubbedScreens: [CGRect] = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    var stubbedCapturedWindowState = WindowState(
        frame: WindowFrame(x: 0, y: 0, width: 1024, height: 768), zoom: 1.0)

    func createWidgetWindow(initialFrame: WindowFrame, autoplayPolicy: WidgetConfig.AutoplayPolicy) -> WidgetWindowHandle {
        createdAutoplayPolicies.append(autoplayPolicy)
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

    /// Stands in for the settings window (or any non-widget window) being in front.
    var stubbedAnotherWindowIsKey = false

    func isAnotherWindowKey(than window: WidgetWindowHandle) -> Bool {
        stubbedAnotherWindowIsKey
    }

    func activateApp() {
        activateAppCallCount += 1
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

    func setMinimumFontSize(_ size: Int?, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        minimumFontSizeChanges.append((size, handle.id))
    }

    func setSnapEnabled(_ enabled: Bool, in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        snapEnabledChanges.append((enabled, handle.id))
    }

    // #83
    private(set) var hotkeyQuickReferences: [(entries: [HotkeyQuickReferenceEntry], windowID: Int)] = []

    func setHotkeyQuickReference(_ entries: [HotkeyQuickReferenceEntry], in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        hotkeyQuickReferences.append((entries, handle.id))
    }

    // #72: 高级 pane
    private(set) var webInspectableChanges: [(enabled: Bool, windowID: Int)] = []
    private(set) var httpWarningChanges: [(enabled: Bool, windowID: Int)] = []
    private(set) var removeAllWebsiteDataCallCount = 0

    func setWebInspectable(_ enabled: Bool, in window: WidgetWindowHandle) {
        webInspectableChanges.append((enabled, (window as! FakeWidgetWindowHandle).id))
    }

    func setHTTPWarningEnabled(_ enabled: Bool, in window: WidgetWindowHandle) {
        httpWarningChanges.append((enabled, (window as! FakeWidgetWindowHandle).id))
    }

    func removeAllWebsiteData() {
        removeAllWebsiteDataCallCount += 1
    }

    func createTrayIcon(items: [TrayMenuItem]) {
        createTrayIconCallCount += 1
        trayMenuItems = items
    }

    /// The tray entry titled `title` — by name rather than index, so reordering the menu (#63)
    /// doesn't silently retarget a test at a neighbouring entry.
    func trayItem(_ title: String) -> TrayMenuItem {
        guard let item = trayMenuItems.first(where: { !$0.isSeparator && $0.title == title }) else {
            preconditionFailure("no tray entry titled \(title)")
        }
        return item
    }

    func terminateApp() {
        terminateAppCallCount += 1
    }

    func reloadPage(in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        reloadedWindowIDs.append(handle.id)
    }

    func stopLoading(in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        stoppedLoadingWindowIDs.append(handle.id)
    }

    func navigationState(of window: WidgetWindowHandle) -> NavigationState {
        stubbedNavigationState
    }

    /// `goBack(in:)`/`goForward(in:)` calls (#59), by window id.
    private(set) var wentBackWindowIDs: [Int] = []
    private(set) var wentForwardWindowIDs: [Int] = []

    func goBack(in window: WidgetWindowHandle) {
        wentBackWindowIDs.append((window as! FakeWidgetWindowHandle).id)
    }

    func goForward(in window: WidgetWindowHandle) {
        wentForwardWindowIDs.append((window as! FakeWidgetWindowHandle).id)
    }

    /// Every `focusAddressBar(in:)` call (#61), with what the window had been through by then —
    /// so a test can assert the focus came after the window was shown and without waiting for
    /// any navigation to finish.
    private(set) var addressBarFocuses: [(windowID: Int, windowWasShown: Bool, loadedURLCount: Int)] = []

    func focusAddressBar(in window: WidgetWindowHandle) {
        let handle = window as! FakeWidgetWindowHandle
        addressBarFocuses.append((handle.id, shownWindowIDs.contains(handle.id), loadedURLs.count))
    }

    func isAccessibilityTrusted() -> Bool {
        stubbedAccessibilityTrusted
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionRequestCount += 1
    }

    func forwardKeystroke(_ keystroke: Hotkey, in window: WidgetWindowHandle) {
        forwardedKeystrokes.append(keystroke)
        forwardedKeystrokeWindowIDs.append((window as! FakeWidgetWindowHandle).id)
    }

    func onPageTitleChanged(_ window: WidgetWindowHandle, perform handler: @escaping (String?) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        pageTitleChangedHandlers[handle.id] = handler
    }

    func simulatePageTitleChanged(_ title: String?, windowID: Int = 1) {
        pageTitleChangedHandlers[windowID]?(title)
    }

    func onEmptyPageVisibilityChanged(_ window: WidgetWindowHandle, perform handler: @escaping (Bool) -> Void) {
        let handle = window as! FakeWidgetWindowHandle
        emptyPageVisibilityChangedHandlers[handle.id] = handler
    }

    func simulateEmptyPageVisibilityChanged(_ visible: Bool, windowID: Int = 1) {
        emptyPageVisibilityChangedHandlers[windowID]?(visible)
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

    // MARK: 网页交互请求 (#66) — each `simulate…` returns the decision MochiCore gave, or `nil`
    // when no handler was registered for that window (nothing would answer WebKit).

    private var javaScriptDialogRequestedHandlers: [Int: (JavaScriptDialogRequest) -> JavaScriptDialogDecision] = [:]
    private var fileUploadRequestedHandlers: [Int: (FileUploadRequest) -> FileUploadDecision] = [:]

    func onJavaScriptDialogRequested(
        _ window: WidgetWindowHandle, perform handler: @escaping (JavaScriptDialogRequest) -> JavaScriptDialogDecision
    ) {
        let handle = window as! FakeWidgetWindowHandle
        javaScriptDialogRequestedHandlers[handle.id] = handler
    }

    func simulateJavaScriptDialogRequested(_ request: JavaScriptDialogRequest, windowID: Int = 1) -> JavaScriptDialogDecision? {
        javaScriptDialogRequestedHandlers[windowID]?(request)
    }

    func onFileUploadRequested(_ window: WidgetWindowHandle, perform handler: @escaping (FileUploadRequest) -> FileUploadDecision) {
        let handle = window as! FakeWidgetWindowHandle
        fileUploadRequestedHandlers[handle.id] = handler
    }

    func simulateFileUploadRequested(_ request: FileUploadRequest, windowID: Int = 1) -> FileUploadDecision? {
        fileUploadRequestedHandlers[windowID]?(request)
    }

    // #68
    private var downloadRequestedHandlers: [Int: (DownloadRequest) -> DownloadDestinationDecision] = [:]

    func onDownloadRequested(_ window: WidgetWindowHandle, perform handler: @escaping (DownloadRequest) -> DownloadDestinationDecision) {
        let handle = window as! FakeWidgetWindowHandle
        downloadRequestedHandlers[handle.id] = handler
    }

    func simulateDownloadRequested(_ request: DownloadRequest, windowID: Int = 1) -> DownloadDestinationDecision? {
        downloadRequestedHandlers[windowID]?(request)
    }

    // #69
    private var mediaCaptureRequestedHandlers: [Int: (MediaCaptureRequest) -> MediaCaptureDecision] = [:]

    func onMediaCaptureRequested(
        _ window: WidgetWindowHandle, perform handler: @escaping (MediaCaptureRequest) -> MediaCaptureDecision
    ) {
        let handle = window as! FakeWidgetWindowHandle
        mediaCaptureRequestedHandlers[handle.id] = handler
    }

    func simulateMediaCaptureRequested(_ request: MediaCaptureRequest, windowID: Int = 1) -> MediaCaptureDecision? {
        mediaCaptureRequestedHandlers[windowID]?(request)
    }

    // MARK: #67: new windows and Popup Windows

    private var newWindowRequestedHandlers: [Int: (NewWindowRequest) -> NewWindowDecision] = [:]
    private(set) var urlsOpenedInDefaultBrowser: [URL] = []
    private(set) var popupWindowsClosedForWindowIDs: [Int] = []
    private(set) var popupWindowsAllowedChanges: [(allowed: Bool, windowID: Int)] = []

    func onNewWindowRequested(_ window: WidgetWindowHandle, perform handler: @escaping (NewWindowRequest) -> NewWindowDecision) {
        let handle = window as! FakeWidgetWindowHandle
        newWindowRequestedHandlers[handle.id] = handler
    }

    func simulateNewWindowRequested(_ request: NewWindowRequest, windowID: Int = 1) -> NewWindowDecision? {
        newWindowRequestedHandlers[windowID]?(request)
    }

    func openInDefaultBrowser(_ url: URL) {
        urlsOpenedInDefaultBrowser.append(url)
    }

    func closePopupWindows(of window: WidgetWindowHandle) {
        popupWindowsClosedForWindowIDs.append((window as! FakeWidgetWindowHandle).id)
    }

    func setPopupWindowsAllowed(_ allowed: Bool, in window: WidgetWindowHandle) {
        popupWindowsAllowedChanges.append((allowed, (window as! FakeWidgetWindowHandle).id))
    }
    // MARK: 视频控制 (#74)

    private var inputHandler: ((RawInputEvent) -> Void)?
    private(set) var startObservingInputCallCount = 0
    private(set) var stopObservingInputCallCount = 0
    private(set) var videoCommands: [(command: VideoCommand, windowID: Int)] = []

    var isObservingInput: Bool { inputHandler != nil }

    func startObservingInput(perform handler: @escaping (RawInputEvent) -> Void) {
        startObservingInputCallCount += 1
        inputHandler = handler
    }

    func stopObservingInput() {
        stopObservingInputCallCount += 1
        inputHandler = nil
    }

    /// Scheduled work waits here until a test calls `runScheduledWork()` — the stand-in for time
    /// passing (#91).
    private var scheduledWork: [(id: Int, work: () -> Void)] = []
    private var nextScheduledWorkID = 0

    var pendingScheduledWorkCount: Int { scheduledWork.count }

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        nextScheduledWorkID += 1
        let id = nextScheduledWorkID
        scheduledWork.append((id, work))
        return { [weak self] in self?.scheduledWork.removeAll { $0.id == id } }
    }

    /// Runs everything scheduled and not cancelled, as if every delay had passed.
    func runScheduledWork() {
        let due = scheduledWork
        scheduledWork = []
        due.forEach { $0.work() }
    }

    func performVideoCommand(_ command: VideoCommand, in window: WidgetWindowHandle) {
        videoCommands.append((command, (window as! FakeWidgetWindowHandle).id))
    }

    // #79
    private(set) var accessibilitySettingsOpenCount = 0

    func openAccessibilitySettings() {
        accessibilitySettingsOpenCount += 1
    }

    // #76
    private(set) var mediaPausedWindowIDs: [Int] = []

    func pauseAllMedia(in window: WidgetWindowHandle) {
        mediaPausedWindowIDs.append((window as! FakeWidgetWindowHandle).id)
    }

    /// Delivers one raw event, as the platform's listener would. Dropped while not observing —
    /// exactly what a real listener that was never installed (or was removed) does.
    func simulateInput(_ event: RawInputEvent) {
        inputHandler?(event)
    }

    /// Presses `key` alone at `time` and releases it `holdFor` seconds later.
    func simulateModifierTap(_ key: ModifierKey, at time: TimeInterval = 100, holdFor: TimeInterval = 0.1) {
        simulateInput(.modifierChanged(keyCode: key.keyCode, held: [key], lastPressAt: 0, timestamp: time))
        simulateInput(.modifierChanged(keyCode: key.keyCode, held: [], lastPressAt: 0, timestamp: time + holdFor))
    }
}
