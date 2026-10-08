import Foundation

// MARK: - 网页交互请求接缝 (#66)
//
// A page can ask Mochi for something only a user can answer: a JavaScript dialog, a file to
// upload — and, in follow-up tickets, a new window (#67), a download (#68), camera/microphone
// access (#69). Every such request crosses the platform boundary the same way:
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

// MARK: - 摄像头与麦克风 (#69)

/// Which capture devices a page's `getUserMedia` asks for.
public enum MediaCaptureDevice: Equatable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
}

/// A page's camera/microphone request (#69).
public struct MediaCaptureRequest: Equatable, Sendable {
    public var device: MediaCaptureDevice
    /// The requesting origin's host — `nil` when it has none.
    public var host: String?

    public init(device: MediaCaptureDevice, host: String?) {
        self.device = device
        self.host = host
    }
}

/// How a camera/microphone request is settled — one-to-one with WebKit's `WKPermissionDecision`,
/// so the AppKit layer only translates.
public enum MediaCaptureDecision: Equatable, Sendable {
    /// Hand it to WebKit's own permission prompt. Mochi does not remember the user's answer there:
    /// remembering would introduce per-site state, and Settings are global (CONTEXT.md「Settings」).
    case prompt
    case grant
    case deny

    /// The decision for `request` given the two 网页内容 settings and the live mode. Ghost Mode
    /// always denies, without a prompt ("不打扰"); a camera+microphone request takes the stricter
    /// of the two settings (拒绝 > 询问 > 允许), so each setting still holds for its own device.
    public static func deciding(
        _ request: MediaCaptureRequest, camera: WidgetConfig.MediaCapturePermission,
        microphone: WidgetConfig.MediaCapturePermission, isGhostModeActive: Bool
    ) -> MediaCaptureDecision {
        guard !isGhostModeActive else { return .deny }
        let permission: WidgetConfig.MediaCapturePermission
        switch request.device {
        case .camera: permission = camera
        case .microphone: permission = microphone
        case .cameraAndMicrophone: permission = camera.strictness >= microphone.strictness ? camera : microphone
        }
        switch permission {
        case .ask: return .prompt
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
