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
