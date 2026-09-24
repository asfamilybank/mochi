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
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void
    ) {
        let request = JavaScriptDialogRequest(kind: .confirm, message: message, host: Self.host(of: frame))
        guard decide(request) == .presentSheet else { return completionHandler(false) }
        let alert = makeDialogAlert(for: request, buttons: ["好", "取消"])
        alert.beginSheetModal(for: window) { response in
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
        alert.beginSheetModal(for: window) { response in
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
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // MARK: Helpers

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
