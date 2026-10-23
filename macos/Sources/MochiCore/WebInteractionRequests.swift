import Foundation

// MARK: - 网页交互请求接缝 (#66)
//
// A page can ask Mochi for something only a user can answer: a JavaScript dialog, a file to
// upload, a new window (#67), a download (#68), camera/microphone access (#69), the mouse pointer
// (pointer lock). Every such request crosses the platform boundary the same way:
//
// - The AppKit layer translates one WebKit delegate callback into a *request* value and hands it
//   to the handler registered through a per-kind `PlatformOps.on…Requested` hook.
// - `MochiCore` (`Orchestrator`) answers synchronously with a *decision* value, reading Ghost Mode
//   state live — never cached — so CONTEXT.md's "不打扰" rule is decided, and tested, in one place.
// - The AppKit layer executes the decision and calls WebKit's completion handler.
//
// Each kind owns its own request/decision pair and its own registration hook. Adding a kind means
// adding a new pair and a new hook next to these — never a new case in an existing type — so the
// kinds below stay untouched as the seam grows, and each decision vocabulary fits only its kind
// (a download's decision is a destination, not "present / settle").

/// What a page's `alert` / `confirm` / `prompt` is asking for.
public enum JavaScriptDialogKind: Equatable, Sendable {
    case alert
    case confirm
    /// `defaultText` pre-fills the input field.
    case prompt(defaultText: String?)
}

/// A page's JavaScript dialog (#66).
public struct JavaScriptDialogRequest: Equatable, Sendable {
    public var kind: JavaScriptDialogKind
    public var message: String
    /// The requesting frame's host — `nil` when it has none (`data:`/`about:` pages).
    public var host: String?

    public init(kind: JavaScriptDialogKind, message: String, host: String?) {
        self.kind = kind
        self.message = message
        self.host = host
    }

    /// The sheet's title: "「host」网页显示", Safari's wording, so the user can see who is asking.
    /// A page without a host (a `data:` URL) gets "此网页显示" rather than an empty 「」.
    public var sheetTitle: String {
        guard let host, !host.isEmpty else { return "此网页显示" }
        return "「\(host)」网页显示"
    }
}

/// How a JavaScript dialog request is settled.
public enum JavaScriptDialogDecision: Equatable, Sendable {
    /// Show it as a sheet on the requesting window and pass the user's answer back.
    case presentSheet
    /// Settle it without any UI (Ghost Mode): `alert` completes, `confirm` answers false, `prompt`
    /// answers null — the page is never left waiting.
    case settleWithoutUI
}

/// A page's file-upload request (`<input type=file>`, #66), with the page's own constraints.
public struct FileUploadRequest: Equatable, Sendable {
    public var allowsMultipleSelection: Bool
    public var allowsDirectories: Bool

    public init(allowsMultipleSelection: Bool, allowsDirectories: Bool) {
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsDirectories = allowsDirectories
    }
}

/// How a file-upload request is settled.
public enum FileUploadDecision: Equatable, Sendable {
    /// Show the system Open panel as a sheet, honouring the request's selection options.
    case presentOpenPanel
    /// Complete as if the user cancelled (Ghost Mode) — no UI.
    case cancel
}

// MARK: Download (#68)

/// A page's download (#68): a navigation WebKit can't show, or a link with a `download`
/// attribute, has become a `WKDownload` and needs somewhere on disk to land.
public struct DownloadRequest: Equatable, Sendable {
    /// WebKit's suggestion (from `Content-Disposition`, the `download` attribute or the URL).
    public var suggestedFilename: String

    public init(suggestedFilename: String) {
        self.suggestedFilename = suggestedFilename
    }
}

/// Where a download lands — decided by `DownloadDestination.decide`; the platform only executes it.
public enum DownloadDestinationDecision: Equatable, Sendable {
    /// Write straight to this file URL. Already made unique (a " (n)" suffix), so nothing that
    /// exists is overwritten.
    case saveTo(URL)
    /// 每次询问 in Normal Mode: show the Save panel as a sheet, opened on `directory` with
    /// `suggestedFilename` pre-filled. Cancelling the panel cancels the download.
    case askWithSavePanel(directory: URL, suggestedFilename: String)
}

// MARK: Download outcome (#105, ADR-0026)

/// How writing a download's file went — the only way Mochi learns where the Downloads folder's
/// 文件和文件夹 permission stands, since the system offers no query for it.
public enum DownloadWriteResult: Equatable, Sendable {
    case succeeded
    /// The system refused the write: for the Downloads folder, the permission is off.
    case deniedPermission
    /// Anything else — the network, a full disk, a cancel. Says nothing about the permission.
    case failed

    /// What a download ending with `error` (`nil`: it finished) means. An error that wraps another
    /// (`NSUnderlyingErrorKey`) is judged by what it wraps; a bare "couldn't create / open the
    /// file" from WebKit's URL loading counts as a refusal, since that is what it means for a
    /// folder that exists.
    public static func classifying(_ error: Error?) -> DownloadWriteResult {
        guard let error else { return .succeeded }
        return isPermissionError(error as NSError) ? .deniedPermission : .failed
    }

    private static func isPermissionError(_ error: NSError) -> Bool {
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        if let underlying, isPermissionError(underlying) { return true }
        switch error.domain {
        case NSCocoaErrorDomain:
            return [CocoaError.fileWriteNoPermission.rawValue, CocoaError.fileReadNoPermission.rawValue]
                .contains(error.code)
        case NSPOSIXErrorDomain:
            return [Int(EPERM), Int(EACCES)].contains(error.code)
        case NSURLErrorDomain:
            return underlying == nil
                && [URLError.cannotCreateFile.rawValue, URLError.cannotOpenFile.rawValue].contains(error.code)
        default:
            return false
        }
    }
}

/// A download that has ended (#105) — reported whether it finished or failed, once it had a
/// destination.
public struct DownloadOutcome: Equatable, Sendable {
    public var destination: URL
    /// The user picked `destination` in a Save panel (每次询问, or 存到其他位置…): the system lets
    /// Mochi write there whatever the 文件和文件夹 permission says, so the outcome tells nothing
    /// about it.
    public var chosenInSavePanel: Bool
    public var result: DownloadWriteResult

    public init(destination: URL, chosenInSavePanel: Bool, result: DownloadWriteResult) {
        self.destination = destination
        self.chosenInSavePanel = chosenInSavePanel
        self.result = result
    }
}

/// What follows a download's end.
public enum DownloadOutcomeDecision: Equatable, Sendable {
    /// Nothing to show.
    case none
    /// Normal Mode, refused by the Downloads folder: a sheet 「无法存到下载文件夹」 with 打开系统设置,
    /// 存到其他位置… and 取消, whose answer goes back as a `DownloadsFolderDeniedAnswer`.
    case offerAnotherLocation
}

/// The user's answer to 「无法存到下载文件夹」 (`DownloadOutcomeDecision.offerAnotherLocation`).
public enum DownloadsFolderDeniedAnswer: Equatable, Sendable {
    case openSystemSettings
    case saveElsewhere
    case cancel
}

/// What the platform does after that answer. Opening System Settings isn't one of these: MochiCore
/// does it itself through `PlatformOps.openSystemSettings(for:)` and answers `.none`.
public enum DownloadsFolderDeniedFollowUp: Equatable, Sendable {
    case none
    /// Show a Save panel (the failed file's name pre-filled), then start the download's original
    /// request again, landing where the user picked — a place the permission doesn't govern.
    case saveElsewhereWithSavePanel
}

// MARK: - 摄像头与麦克风 (#69) · 网站例外与 Mochi 的询问框 (#101, ADR-0027)

/// Which capture devices a page's `getUserMedia` asks for.
public enum MediaCaptureDevice: Equatable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone

    /// The 网页权限 this request needs — both for a camera+microphone request.
    public var pagePermissions: [PagePermission] {
        switch self {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        }
    }

    /// How the prompt names the device.
    var displayName: String {
        switch self {
        case .camera: "摄像头"
        case .microphone: "麦克风"
        case .cameraAndMicrophone: "摄像头和麦克风"
        }
    }
}

/// A 网页权限 (CONTEXT.md「网页权限」): each has a「访问其他网站时」default plus per-website
/// exceptions in `WidgetConfig`.
public enum PagePermission: String, CaseIterable, Sendable {
    case camera
    case microphone
}

/// Which of a widget's web views a request came from: the widget's own page, or one of its Popup
/// Windows — `id` tells the popups apart while they are open.
public enum WebViewSource: Hashable, Sendable {
    case widget
    case popupWindow(id: Int)
}

/// A page's camera/microphone request (#69).
public struct MediaCaptureRequest: Equatable, Sendable {
    public var device: MediaCaptureDevice
    /// The requesting *frame's* host — a meeting iframe counts as the meeting service, not the page
    /// around it (#101). Lower-cased; `nil` when it has none (`data:`, `file:`).
    public var host: String?
    public var source: WebViewSource

    public init(device: MediaCaptureDevice, host: String?, source: WebViewSource = .widget) {
        self.device = device
        let host = host?.lowercased()
        self.host = host?.isEmpty == false ? host : nil
        self.source = source
    }
}

/// One 「仅这次允许」 answer, held for the page load of the web view it was given in.
public struct MediaCaptureGrant: Hashable, Sendable {
    public var host: String
    public var permission: PagePermission

    public init(host: String, permission: PagePermission) {
        self.host = host
        self.permission = permission
    }
}

/// How a camera/microphone request is settled.
public enum MediaCaptureDecision: Equatable, Sendable {
    /// Mochi asks the user with its own sheet (`MediaCapturePrompt`) on the requesting window, and
    /// WebKit gets its decision once the answer is back. Never WebKit's own prompt: that one would
    /// not tell Mochi what the user chose, so nothing could be remembered (ADR-0027).
    case ask
    case grant
    case deny

    /// The decision for `request` (ADR-0027):
    ///
    /// - 不打扰 (Ghost Mode) denies a request from the widget's page without asking; a Popup
    ///   Window is an ordinary window the user may be working in, so its requests go through the
    ///   rules as usual.
    /// - Each permission the request needs is the host's exception, or the default when the host
    ///   has none (always the default for a host-less page). A 「仅这次允许」 grant of the same
    ///   page load turns 询问 into 允许 — never a 拒绝 the user has set since.
    /// - A camera+microphone request takes the stricter of the two (拒绝 > 询问 > 允许).
    public static func deciding(
        _ request: MediaCaptureRequest, config: WidgetConfig, doNotDisturb: Bool,
        grantedThisTime: Set<MediaCaptureGrant>
    ) -> MediaCaptureDecision {
        if doNotDisturb, request.source == .widget { return .deny }
        let settings = request.device.pagePermissions.map { permission -> WidgetConfig.MediaCapturePermission in
            let setting = config.pagePermissionSetting(permission, forHost: request.host)
            if setting == .ask, let host = request.host,
                grantedThisTime.contains(MediaCaptureGrant(host: host, permission: permission))
            {
                return .allow
            }
            return setting
        }
        switch settings.max(by: { $0.strictness < $1.strictness }) ?? .deny {
        case .ask: return .ask
        case .allow: return .grant
        case .deny: return .deny
        }
    }
}

extension WidgetConfig.MediaCapturePermission {
    /// Higher is stricter: 拒绝 > 询问 > 允许.
    fileprivate var strictness: Int {
        switch self {
        case .allow: 0
        case .ask: 1
        case .deny: 2
        }
    }
}

/// What the user picked in Mochi's prompt.
public enum MediaCapturePromptAnswer: Equatable, Sendable {
    /// 访问此网站时允许 — remembered as an 允许 exception for the host.
    case allowOnThisSite
    /// 仅这次允许 (plain 允许 on a host-less page) — held for this page load only.
    case allowThisTime
    /// 不允许 — remembered as a 拒绝 exception for the host; a host-less page remembers nothing.
    case deny
}

/// The sheet Mochi shows for an `.ask` decision: the host and the device in the title, Chrome's
/// three choices — or just 允许 / 不允许 when the page has no host to remember anything under.
public struct MediaCapturePrompt: Equatable, Sendable {
    public struct Choice: Equatable, Sendable {
        public var answer: MediaCapturePromptAnswer
        public var title: String
    }

    public var title: String
    /// In display order, top to bottom.
    public var choices: [Choice]

    public init(for request: MediaCaptureRequest) {
        if let host = request.host {
            title = "“\(host)”想使用你的\(request.device.displayName)"
            choices = [
                Choice(answer: .allowOnThisSite, title: "访问此网站时允许"),
                Choice(answer: .allowThisTime, title: "仅这次允许"),
                Choice(answer: .deny, title: "不允许"),
            ]
        } else {
            title = "此网页想使用你的\(request.device.displayName)"
            choices = [
                Choice(answer: .allowThisTime, title: "允许"),
                Choice(answer: .deny, title: "不允许"),
            ]
        }
    }
}

// MARK: New windows (#67)

/// What made the page ask for a new window.
public enum NewWindowTrigger: Equatable, Sendable {
    /// The user clicked a link (`target=_blank`, or any link while holding ⌘) —
    /// `WKNavigationType.linkActivated`. `commandPressed` is whether ⌘ was held.
    case linkClick(commandPressed: Bool)
    /// Anything else that reaches WebKit's new-window delegate — in practice a `window.open` run
    /// from a click handler (an OAuth login window). A popup with no user gesture never gets this
    /// far while 弹出式窗口 is 阻止: WebKit drops it itself (ADR-0017).
    case script
}

/// Which window a new-window request came from.
public enum NewWindowOpener: Equatable, Sendable {
    case widget
    /// One of the widget's Popup Windows (CONTEXT.md).
    case popupWindow
}

/// A page's request to open a new window (#67).
public struct NewWindowRequest: Equatable, Sendable {
    public var trigger: NewWindowTrigger
    public var opener: NewWindowOpener
    /// The page the new window would show — `nil` when WebKit gives none (a script opening
    /// `about:blank` to write into).
    public var url: URL?

    public init(trigger: NewWindowTrigger, opener: NewWindowOpener, url: URL?) {
        self.trigger = trigger
        self.opener = opener
        self.url = url
    }
}

/// How a new-window request is settled. Handing a ⌘-clicked link to the default browser is not
/// something the platform executes from a decision: MochiCore does it itself through
/// `PlatformOps.openInDefaultBrowser` and answers `.cancel`, so the page opens nothing.
public enum NewWindowDecision: Equatable, Sendable {
    /// Load the request in the window that made it — the widget, or the requesting Popup Window
    /// (so popups never multiply).
    case loadInOpener
    /// Open a Popup Window built from the configuration WebKit passes in (shared website data and
    /// `window.opener`).
    case openPopupWindow
    /// Open nothing.
    case cancel
}

// MARK: Pointer lock

/// A page's `requestPointerLock()`: a browser game hides the pointer and reads the mouse's raw
/// movement to turn its camera. WebKit only passes on a request made from a click or key press in
/// the page, and hands the pointer back by itself once the window stops being key.
public struct PointerLockRequest: Equatable, Sendable {
    public var source: WebViewSource

    public init(source: WebViewSource = .widget) {
        self.source = source
    }
}

/// How a pointer-lock request is settled.
public enum PointerLockDecision: Equatable, Sendable {
    case grant
    case deny
}
