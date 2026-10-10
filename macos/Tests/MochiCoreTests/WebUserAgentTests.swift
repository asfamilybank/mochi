import Foundation
import Testing

@testable import MochiCore

@Suite struct WebUserAgentTests {
    /// Safari's User-Agent names only major.minor, so a patch release is cut back to that; a bare
    /// major gains `.0`. `nil` stands for "the key is not in the dictionary at all".
    @Test(arguments: [(raw: String?("26.5.2"), expected: "Version/26.5 Safari/605.1.15"),
                      (raw: String?("26.5"), expected: "Version/26.5 Safari/605.1.15"),
                      (raw: String?("27"), expected: "Version/27.0 Safari/605.1.15"),
                      (raw: String?(nil), expected: "Version/26.0 Safari/605.1.15"),
                      (raw: String?(""), expected: "Version/26.0 Safari/605.1.15"),
                      (raw: String?("26.x"), expected: "Version/26.0 Safari/605.1.15")])
    func suffixNamesTheInstalledSafarisVersion(argument: (raw: String?, expected: String)) {
        let info: [String: Any] = argument.raw.map { ["CFBundleShortVersionString": $0] } ?? [:]
        #expect(WebUserAgent.applicationName(fromSafariInfoDictionary: info) == argument.expected)
    }

    /// No readable Safari bundle at all is the same fallback, not a crash.
    @Test func suffixFallsBackWithNoInfoDictionary() {
        #expect(WebUserAgent.applicationName(fromSafariInfoDictionary: nil) == "Version/26.0 Safari/605.1.15")
    }

    /// The cache is stale whenever the suffix moved — a Safari update, or no record at all (every
    /// install from before the check, whose cache may hold redirects under the bare User-Agent).
    @Test(arguments: [(lastReported: String?("Version/26.5 Safari/605.1.15"), stale: false),
                      (lastReported: String?("Version/26.4 Safari/605.1.15"), stale: true),
                      (lastReported: String?(nil), stale: true)])
    func httpCacheIsStaleWhenTheSuffixChanged(argument: (lastReported: String?, stale: Bool)) {
        #expect(WebUserAgent.httpCacheIsStale(
            lastReported: argument.lastReported, current: "Version/26.5 Safari/605.1.15") == argument.stale)
    }
}
