import Foundation
import Testing

@testable import MochiCore

@Suite struct AppInfoTests {
    /// One table over the three branches that matter: a version the bundle carries is passed
    /// through verbatim, a missing key falls back, and so does a present-but-blank one. `nil`
    /// stands for "the key is not in the dictionary at all", which covers both running from
    /// source and an unstamped `.app` — an empty `MARKETING_VERSION` makes Xcode drop the key
    /// rather than write it through blank. `""` is the belt-and-braces row; see `AppInfo`.
    @Test(arguments: [(raw: String?("1.2.3"), expected: "1.2.3"),
                      (raw: String?("0.1.0-beta.2"), expected: "0.1.0-beta.2"),
                      (raw: String?(nil), expected: AppInfo.developmentVersion),
                      (raw: String?(""), expected: AppInfo.developmentVersion),
                      (raw: String?("   "), expected: AppInfo.developmentVersion)])
    func versionComesFromTheBundleUnlessItIsMissingOrBlank(argument: (raw: String?, expected: String)) {
        let info: [String: Any] = argument.raw.map { ["CFBundleShortVersionString": $0] } ?? [:]
        #expect(AppInfo.version(fromInfoDictionary: info) == argument.expected)
    }

    /// Running from source — `swift run`, the whole of the development loop — has no bundle at
    /// all, which is a step beyond the table's missing-key row.
    @Test func versionFallsBackWithNoInfoDictionary() {
        #expect(AppInfo.version(fromInfoDictionary: nil) == AppInfo.developmentVersion)
    }

    /// An info dictionary is `[String: Any]`, so a malformed plist can hand back a number where a
    /// string belongs; that is a missing version, not a crash.
    @Test func versionFallsBackWhenTheValueIsNotAString() {
        #expect(AppInfo.version(fromInfoDictionary: ["CFBundleShortVersionString": 3]) == AppInfo.developmentVersion)
    }

    /// The fallback is deliberately not a version number — see `AppInfo.developmentVersion`.
    @Test func theFallbackIsNotMistakableForAReleaseVersion() {
        #expect(AppInfo.developmentVersion.first(where: \.isNumber) == nil)
    }
}
