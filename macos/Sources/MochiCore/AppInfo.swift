import Foundation

/// What the app reports about itself — currently just to the standard About panel (#37).
///
/// The name is a constant; the version deliberately is not. It used to be a hand-bumped literal
/// because a process launched by `swift run` has no bundle to read `CFBundleShortVersionString`
/// from. Packaging (ADR-0014) made git tags the single source of truth: the packaging script
/// stamps the tag into `Info.plist`, so a bundled build reads its version back from there and a
/// literal in the source would only be a second, staler copy.
public enum AppInfo {
    public static let name = "Mochi"

    /// Reported by any build that has no stamped version — in practice, running from source.
    /// Deliberately not a number: a plausible-looking one would invite mistaking a working copy
    /// for the release that happens to share it.
    public static let developmentVersion = "dev"

    private static let versionKey = "CFBundleShortVersionString"

    /// The version to display, given a bundle's info dictionary — `Bundle.main.infoDictionary`
    /// at the call site. Taking the dictionary rather than reading `Bundle.main` here keeps this
    /// a pure function of its input, so the fallback is testable without a bundle to run in.
    ///
    /// Anything unusable — no dictionary, no key, a non-string, or a blank string — falls back
    /// to `developmentVersion`.
    ///
    /// The missing-key branch carries bundled builds too, not just `swift run`: the Xcode project
    /// ships `MARKETING_VERSION` deliberately *empty*, so only the packaging script's
    /// `xcodebuild MARKETING_VERSION=…` stamps a real one — and an empty build setting makes
    /// Xcode drop `CFBundleShortVersionString` from the built `Info.plist` altogether (measured;
    /// it does not substitute an empty string as one might expect). An unstamped `.app` therefore
    /// reports "dev" exactly like running from source, which is what ADR-0014 means by git tags
    /// being the only place a version number is written down.
    ///
    /// The blank-string branch is then belt-and-braces rather than the mechanism — it costs one
    /// condition and covers a hand-edited plist, or a future Xcode that starts substituting the
    /// empty value through instead of dropping the key.
    public static func version(fromInfoDictionary info: [String: Any]?) -> String {
        guard let raw = info?[versionKey] as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return developmentVersion }
        return raw
    }
}
