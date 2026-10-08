import Foundation

/// The User-Agent suffix every web view in Mochi reports, so sites see a Safari rather than an
/// unidentifiable WebKit embed.
///
/// A bare `WKWebView`'s User-Agent stops after `(KHTML, like Gecko)` — no `Version/…` and no
/// `Safari/…` token. Sites that gate on browser version read that as an ancient or unknown
/// browser: bilibili.com redirects every visit to its 「您的浏览器版本过低」 page (measured on
/// macOS 26.5; the same page loads normally once the suffix is there). The suffix goes in through
/// `WKWebViewConfiguration.applicationNameForUserAgent`, which WebKit appends after its own
/// prefix, rather than a whole `customUserAgent` string — the prefix (platform, WebKit version)
/// stays WebKit's to keep current.
///
/// The version is the installed Safari's. On macOS, Safari and the system WebKit ship together,
/// so it names exactly the engine this web view is running — claiming a hard-coded version would
/// drift out of date with every OS update, and too old a number is the very thing that trips
/// version gates.
public enum WebUserAgent {
    /// Where the installed Safari's bundle lives; read at web view creation.
    public static let safariInfoPlistURL = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")

    /// Used when the installed Safari's version can't be read — the macOS baseline (ADR-0008),
    /// so it is never older than the engine actually running.
    static let fallbackSafariVersion = "26.0"

    /// Safari's own trailing token: a frozen WebKit build number, the same on every current
    /// Safari (and on WebKit's own prefix here).
    static let safariToken = "Safari/605.1.15"

    /// The suffix for the Safari whose `Info.plist` is `info` — the installed one's at the call
    /// site; taking the dictionary keeps this a pure function of its input, like
    /// `AppInfo.version(fromInfoDictionary:)`.
    ///
    /// Safari reports only major.minor (`26.5.2` → `Version/26.5`), so the version is cut to its
    /// first two components; anything unusable falls back to `fallbackSafariVersion`.
    public static func applicationName(fromSafariInfoDictionary info: [String: Any]?) -> String {
        "Version/\(safariVersion(from: info)) \(safariToken)"
    }

    private static func safariVersion(from info: [String: Any]?) -> String {
        guard let raw = info?["CFBundleShortVersionString"] as? String else { return fallbackSafariVersion }
        let components = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard let major = components.first, !major.isEmpty, components.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return fallbackSafariVersion }
        return components.count > 1 ? "\(major).\(components[1])" : "\(major).0"
    }
}
