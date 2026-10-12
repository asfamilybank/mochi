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
        // #105: a download restarted by 存到其他位置… already has its place, from the Save panel.
        if let url = restartedDownloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
            downloadDestinations[ObjectIdentifier(download)] = url
            downloadsChosenInSavePanel.insert(ObjectIdentifier(download))
            return completionHandler(url)
        }
        // No decider registered means nobody may choose a place on disk: cancel.
        guard let decide = downloadRequestedHandler else { return completionHandler(nil) }
        // The answer may come later (#99): deciding reads the disk off the main thread, and the
        // first read of ~/Downloads waits until the system's 「访问下载文件夹」 prompt is answered.
        decide(DownloadRequest(suggestedFilename: suggestedFilename)) { [weak self] decision in
            guard let self else { return completionHandler(nil) }
            execute(decision, for: download, completionHandler: completionHandler)
        }
    }

    /// Carries out MochiCore's answer on the main thread: hand WebKit the file URL, or ask first
    /// with a Save panel sheet.
    private func execute(
        _ decision: DownloadDestinationDecision, for download: WKDownload,
        completionHandler: @escaping (URL?) -> Void
    ) {
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
                self?.downloadsChosenInSavePanel.insert(ObjectIdentifier(download))  // #105
                completionHandler(url)
            }
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        Self.bounceDownloadsStack(for: url)
        reportEnd(of: download, at: url, error: nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        restartedDownloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        // A download that failed before it had a destination wrote nothing: nothing to report.
        guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        reportEnd(of: download, at: url, error: error)
    }

    // MARK: When the Downloads folder refuses the write (#105, ADR-0026)

    /// Tells MochiCore how the write went — the only reading of the Downloads folder's permission
    /// there is — and carries out its answer.
    private func reportEnd(of download: WKDownload, at destination: URL, error: Error?) {
        let chosenInSavePanel = downloadsChosenInSavePanel.remove(ObjectIdentifier(download)) != nil
        let outcome = DownloadOutcome(
            destination: destination, chosenInSavePanel: chosenInSavePanel, result: .classifying(error))
        guard downloadEndedHandler?(outcome) == .offerAnotherLocation else { return }
        offerAnotherLocation(for: download.originalRequest, filename: destination.lastPathComponent)
    }

    /// 「无法存到下载文件夹」 as a sheet on the widget; the answer goes back to MochiCore, which
    /// opens System Settings itself or has this code save the file elsewhere.
    private func offerAnotherLocation(for request: URLRequest?, filename: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法存到下载文件夹"
        alert.informativeText =
            "Mochi 没有访问「下载」文件夹的权限，“\(filename)”没能存下来。可以在系统设置的「文件和文件夹」里允许 Mochi 访问，或者这次存到其他位置。"
        // The default button finishes what the user set out to do.
        alert.addButton(withTitle: "存到其他位置…")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            let answer: DownloadsFolderDeniedAnswer =
                switch response {
                case .alertFirstButtonReturn: .saveElsewhere
                case .alertSecondButtonReturn: .openSystemSettings
                default: .cancel
                }
            guard let self, downloadsFolderDeniedAnsweredHandler?(answer) == .saveElsewhereWithSavePanel, let request
            else { return }
            // After the alert's sheet has fully gone, so the Save panel can take its place.
            DispatchQueue.main.async { [weak self] in self?.saveElsewhere(request, filename: filename) }
        }
    }

    /// A Save panel, then the same request again, landing where the user picked — a place the
    /// Downloads folder's permission doesn't govern (the panel grants it).
    private func saveElsewhere(_ request: URLRequest, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            // As for 每次询问: the panel already asked "replace?", and WebKit won't write over a file.
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            webView.startDownload(using: request) { [weak self] download in
                guard let self else { return download.cancel() }
                restartedDownloadDestinations[ObjectIdentifier(download)] = url
                download.delegate = self
            }
        }
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
