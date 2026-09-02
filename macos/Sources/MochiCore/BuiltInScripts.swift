import Foundation

/// An officially maintained site-adapter script (#7), bundled with the app and updated alongside
/// it — distinct from a user's own custom script, which carries the same technical permissions
/// but is flagged as "use at your own risk" wherever scripts are surfaced in the UI.
public struct BuiltInScript: Equatable {
    public let id: String
    public let displayName: String
    public let source: String

    public init(id: String, displayName: String, source: String) {
        self.id = id
        self.displayName = displayName
        self.source = source
    }
}

public enum BuiltInScripts {
    /// Focuses the page's `<video>` element after load, so a hotkey forwarded via
    /// `CGEventPostToPid` (ADR-0003) lands on the player instead of being swallowed by whatever
    /// element happened to hold focus (e.g. a search box or an ad iframe).
    public static let genericVideoFocus = BuiltInScript(
        id: "generic-video-focus",
        displayName: "通用视频对焦适配",
        source: """
        (function () {
            var video = document.querySelector('video');
            if (video) { video.focus(); }
        })();
        """
    )

    public static let all: [BuiltInScript] = [genericVideoFocus]
}
