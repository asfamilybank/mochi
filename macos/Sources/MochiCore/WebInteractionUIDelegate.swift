import AppKit
import WebKit

/// The AppKit half of the 网页交互请求 seam (#66, see `WebInteractionRequests.swift`): each
/// `WKUIDelegate` callback is translated into a request, MochiCore's decider answers, and this
/// code only executes the answer — every path calls WebKit's completion handler exactly once.
///
/// Later request kinds (#67 new windows, #69 media capture) add their `WKUIDelegate` methods to
/// this extension rather than declaring the conformance again.
extension AppKitWidgetWindowHandle: WKUIDelegate {
    // MARK: JavaScript dialogs

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void
    ) {
        let request = JavaScriptDialogRequest(kind: .alert, message: message, host: Self.host(of: frame))
        guard decide(request) == .presentSheet else { return completionHandler() }
        let alert = makeDialogAlert(for: request, buttons: ["好"])
        alert.beginSheetModal(for: sheetWindow(for: webView)) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void
    ) {
        let request = JavaScriptDialogRequest(kind: .confirm, message: message, host: Self.host(of: frame))
        guard decide(request) == .presentSheet else { return completionHandler(false) }
        let alert = makeDialogAlert(for: request, buttons: ["好", "取消"])
        alert.beginSheetModal(for: sheetWindow(for: webView)) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void
    ) {
        let request = JavaScriptDialogRequest(
            kind: .prompt(defaultText: defaultText), message: prompt, host: Self.host(of: frame))
        guard decide(request) == .presentSheet else { return completionHandler(nil) }
        let alert = makeDialogAlert(for: request, buttons: ["好", "取消"])
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: sheetWindow(for: webView)) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    // MARK: File upload

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void
    ) {
        let request = FileUploadRequest(
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories)
        let decision = fileUploadRequestedHandler?(request) ?? .cancel
        guard decision == .presentOpenPanel else { return completionHandler(nil) }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = request.allowsDirectories
        panel.allowsMultipleSelection = request.allowsMultipleSelection
        panel.beginSheetModal(for: sheetWindow(for: webView)) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // MARK: Camera & microphone (#69)

    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let device: MediaCaptureDevice
        switch type {
        case .camera: device = .camera
        case .microphone: device = .microphone
        case .cameraAndMicrophone: device = .cameraAndMicrophone
        @unknown default: return decisionHandler(.deny)
        }
        let request = MediaCaptureRequest(device: device, host: origin.host.isEmpty ? nil : origin.host)
        // No decider registered means nobody decided: deny rather than grant or prompt.
        switch mediaCaptureRequestedHandler?(request) ?? .deny {
        case .prompt: decisionHandler(.prompt)
        case .grant: decisionHandler(.grant)
        case .deny: decisionHandler(.deny)
        }
    }

    // MARK: New windows (#67)

    /// `target=_blank` links and `window.open` from the widget's page *or* any of its Popup
    /// Windows (this handle is the popup web views' `uiDelegate` too). Returning a web view is
    /// what opens a Popup Window: WebKit loads the request into it and wires up `window.opener`.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let trigger: NewWindowTrigger =
            navigationAction.navigationType == .linkActivated
            ? .linkClick(commandPressed: navigationAction.modifierFlags.contains(.command)) : .script
        let request = NewWindowRequest(
            trigger: trigger, opener: newWindowOpener(of: webView), url: navigationAction.request.url)
        switch newWindowRequestedHandler?(request) ?? .cancel {
        case .cancel:
            return nil
        case .loadInOpener:
            if navigationAction.request.url != nil { webView.load(navigationAction.request) }
            return nil
        case .openPopupWindow:
            let popup = PopupWindowController(configuration: configuration, windowFeatures: windowFeatures, owner: self)
            popupWindows.append(popup)
            popup.show()
            return popup.webView
        }
    }

    /// The page called `window.close()`. Only a script-opened window may close itself, so this is
    /// a Popup Window's; the widget's own web view is never closed this way.
    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.first { $0.webView === webView }?.close()
    }

    /// A ⌘-clicked link in any of this widget's web views (#67): asked from the navigation policy
    /// decision, before WebKit would load it or ask for a new window. `nil` when the navigation is
    /// not a ⌘-click; otherwise MochiCore's answer (it hands the link to the default browser).
    func commandClickDecision(for action: WKNavigationAction, in webView: WKWebView) -> NewWindowDecision? {
        guard action.navigationType == .linkActivated, action.modifierFlags.contains(.command) else { return nil }
        let request = NewWindowRequest(
            trigger: .linkClick(commandPressed: true), opener: newWindowOpener(of: webView), url: action.request.url)
        return newWindowRequestedHandler?(request) ?? .cancel
    }

    func closePopupWindows() {
        for popup in popupWindows { popup.close() }
        popupWindows.removeAll()
    }

    func popupWindowDidClose(_ popup: PopupWindowController) {
        popupWindows.removeAll { $0 === popup }
    }

    /// Re-pushes the widget's live per-web-view settings to every open Popup Window.
    func applySettingsToPopupWindows() {
        for popup in popupWindows { popup.applySettings(from: self) }
    }

    private func newWindowOpener(of webView: WKWebView) -> NewWindowOpener {
        webView === self.webView ? .widget : .popupWindow
    }

    // MARK: Helpers

    /// The window a dialog/Open panel for `webView` is attached to — the Popup Window's own when
    /// the request came from one (#67), else the widget's.
    private func sheetWindow(for webView: WKWebView) -> NSWindow {
        webView === self.webView ? window : (webView.window ?? window)
    }

    /// Ends every sheet still attached to the widget window — called on teardown, so a window
    /// closed with a dialog or Open panel up still answers WebKit (as a cancel).
    func endWebInteractionSheets() {
        for sheet in window.sheets {
            window.endSheet(sheet, returnCode: .cancel)
        }
    }

    private func decide(_ request: JavaScriptDialogRequest) -> JavaScriptDialogDecision {
        // No decider registered means nobody may show UI: settle rather than hang the page.
        javaScriptDialogRequestedHandler?(request) ?? .settleWithoutUI
    }

    /// `buttons` in NSAlert order: the first is the rightmost default (Return); a "取消" button
    /// also answers Escape.
    private func makeDialogAlert(for request: JavaScriptDialogRequest, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = request.sheetTitle
        alert.informativeText = request.message
        for title in buttons {
            let button = alert.addButton(withTitle: title)
            if title == "取消" { button.keyEquivalent = "\u{1b}" }
        }
        return alert
    }

    private static func host(of frame: WKFrameInfo) -> String? {
        let host = frame.securityOrigin.host
        return host.isEmpty ? nil : host
    }
}
