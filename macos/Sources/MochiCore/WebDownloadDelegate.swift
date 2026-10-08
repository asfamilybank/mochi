import AppKit
import WebKit

/// The AppKit half of the 网页交互请求 seam's download kind (#68, see `WebInteractionRequests.swift`):
/// navigations WebKit can't show become `WKDownload`s, MochiCore decides where each lands
/// (`DownloadDestination`), and this code only executes that answer. No progress UI by design.
///
/// The navigation-action half of the conversion (`shouldPerformDownload`, i.e. a `download`
/// attribute link) lives in the existing `decidePolicyFor navigationAction` method in
/// `AppKitPlatformOps.swift`, which also carries #72's HTTP-warning policy.
extension AppKitWidgetWindowHandle: WKDownloadDelegate {
    // MARK: Turning navigations into downloads

    /// A response WebKit can't display (a zip, a dmg, …) or one the server marks as an attachment
    /// is saved rather than failing to load — what Safari does with the same response.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(
            !navigationResponse.canShowMIMEType || Self.isAttachment(navigationResponse.response) ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKDownloadDelegate

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        // No decider registered means nobody may choose a place on disk: cancel.
        guard let decision = downloadRequestedHandler?(DownloadRequest(suggestedFilename: suggestedFilename)) else {
            return completionHandler(nil)
        }
        switch decision {
        case .saveTo(let url):
            downloadDestinations[ObjectIdentifier(download)] = url
            completionHandler(url)
        case .askWithSavePanel(let directory, let filename):
            let panel = NSSavePanel()
            panel.directoryURL = directory
            panel.nameFieldStringValue = filename
            panel.canCreateDirectories = true
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return completionHandler(nil) }
                // The panel already asked "replace?" for an existing file; WebKit refuses to write
                // over one, so move the old file to the Trash (recoverable) rather than delete it.
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                self?.downloadDestinations[ObjectIdentifier(download)] = url
                completionHandler(url)
            }
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        Self.bounceDownloadsStack(for: url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }

    // MARK: Helpers

    /// Safari's mechanism, also used by Chromium (`download_status_updater_mac.mm`): a distributed
    /// notification named `com.apple.DownloadFileFinished` whose object is the file's path makes
    /// the Dock bounce the stack containing that file — the Downloads stack for the default
    /// location. A file outside any Dock stack simply bounces nothing.
    private static func bounceDownloadsStack(for file: URL) {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.DownloadFileFinished"), object: file.resolvingSymlinksInPath().path)
    }

    private static func isAttachment(_ response: URLResponse) -> Bool {
        guard let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        else { return false }
        return disposition.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("attachment")
    }
}
