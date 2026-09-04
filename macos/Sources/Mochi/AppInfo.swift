/// A source-level stand-in for `Info.plist`'s `CFBundleName`/`CFBundleShortVersionString` — a
/// process launched via `swift run` has no bundle to read those from, so the About panel (#37)
/// needs its own copy rather than depending on packaging (out of scope until the release
/// discussion, per #29).
enum AppInfo {
    static let name = "Mochi"

    /// Bumped by hand until packaging exists to derive it from somewhere authoritative.
    static let version = "0.1.0"
}
