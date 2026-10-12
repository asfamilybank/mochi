import Foundation
import Testing

@testable import MochiCore

/// 管理网站和数据… (#106): website data records and 网页权限 exceptions merged into one list, by
/// WebKit's registrable-domain records, without a public suffix list.
@Suite struct ManagedWebsitesTests {
    private let date = Date(timeIntervalSince1970: 1_000_000)

    private func config(camera: [(String, WidgetConfig.MediaCapturePermission)] = [],
                        microphone: [(String, WidgetConfig.MediaCapturePermission)] = []) -> WidgetConfig {
        var config = WidgetConfig(url: nil)
        for (host, setting) in camera {
            config = config.updatingPagePermissionException(.camera, host: host, setting: setting, modifiedAt: date)
        }
        for (host, setting) in microphone {
            config = config.updatingPagePermissionException(.microphone, host: host, setting: setting, modifiedAt: date)
        }
        return config
    }

    @Test func aSubdomainsExceptionsGoUnderItsRecord() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "google.com", kinds: [.cookies, .cache])],
            exceptionsIn: config(camera: [("meet.google.com", .allow)], microphone: [("meet.google.com", .deny)]))

        #expect(websites == [
            ManagedWebsite(
                domain: "google.com", dataKinds: [.cookies, .cache],
                exceptions: [WebsiteHostExceptions(host: "meet.google.com", camera: .allow, microphone: .deny)])
        ])
    }

    @Test func aHostEqualToARecordsNameGoesUnderIt() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "example.com", kinds: [.localStorage])],
            exceptionsIn: config(camera: [("example.com", .deny)]))

        #expect(websites.map(\.domain) == ["example.com"])
        #expect(websites.first?.exceptions == [WebsiteHostExceptions(host: "example.com", camera: .deny, microphone: nil)])
    }

    @Test func aHostWithoutARecordIsAWebsiteOfItsOwn() {
        let websites = ManagedWebsites.grouping(
            [], exceptionsIn: config(camera: [("meet.google.com", .allow), ("zoom.us", .ask)]))

        #expect(websites == [
            ManagedWebsite(
                domain: "meet.google.com", dataKinds: nil,
                exceptions: [WebsiteHostExceptions(host: "meet.google.com", camera: .allow, microphone: nil)]),
            ManagedWebsite(
                domain: "zoom.us", dataKinds: nil,
                exceptions: [WebsiteHostExceptions(host: "zoom.us", camera: .ask, microphone: nil)]),
        ])
    }

    @Test func aLookalikeDomainIsNotASubdomain() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "google.com", kinds: [.cookies])],
            exceptionsIn: config(camera: [("notgoogle.com", .allow)]))

        #expect(websites.map(\.domain) == ["google.com", "notgoogle.com"])
        #expect(websites[0].exceptions.isEmpty)
        #expect(websites[1].dataKinds == nil)
    }

    @Test func aRecordWithoutExceptionsIsListedForItsData() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "b.com", kinds: [.cookies]), WebsiteDataRecord(displayName: "a.com", kinds: [.cache])],
            exceptionsIn: config())

        #expect(websites.map(\.domain) == ["a.com", "b.com"])
        #expect(websites.allSatisfy { $0.exceptions.isEmpty })
        #expect(websites.allSatisfy { $0.hasData })
    }

    @Test func aHostGoesUnderTheLongestMatchingRecord() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "co.uk", kinds: [.cookies]), WebsiteDataRecord(displayName: "bbc.co.uk", kinds: [.cookies])],
            exceptionsIn: config(camera: [("www.bbc.co.uk", .allow)]))

        #expect(websites.first(where: { $0.domain == "bbc.co.uk" })?.exceptions.map(\.host) == ["www.bbc.co.uk"])
        #expect(websites.first(where: { $0.domain == "co.uk" })?.exceptions.isEmpty == true)
    }

    @Test func dataKindsAreListedInAFixedOrder() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "a.com", kinds: [.other, .cache, .cookies])], exceptionsIn: config())

        #expect(websites.first?.dataKinds == [.cookies, .cache, .other])
    }

    @Test func searchMatchesTheDomainAndTheExceptionHostsIgnoringCase() {
        let websites = ManagedWebsites.grouping(
            [WebsiteDataRecord(displayName: "google.com", kinds: [.cookies]), WebsiteDataRecord(displayName: "zoom.us", kinds: [.cookies])],
            exceptionsIn: config(camera: [("meet.google.com", .allow)]))

        #expect(ManagedWebsites.filtered(websites, matching: "MEET").map(\.domain) == ["google.com"])
        #expect(ManagedWebsites.filtered(websites, matching: "zoom").map(\.domain) == ["zoom.us"])
        #expect(ManagedWebsites.filtered(websites, matching: "  ").map(\.domain) == ["google.com", "zoom.us"])
    }

    /// Websites holding nothing but cache (CDNs, ad servers) crowd the list, so the blank list leaves
    /// them out unless asked; a search looks through everything, whatever the switch says.
    @Test(arguments: [
        (query: "", includingCacheOnly: false, expected: ["example.com", "google.com", "zoom.us"]),
        (query: "", includingCacheOnly: true, expected: ["cdn.net", "example.com", "google.com", "zoom.us"]),
        (query: "cdn", includingCacheOnly: false, expected: ["cdn.net"]),
    ])
    func cacheOnlyWebsitesAreLeftOutOfTheBlankListUnlessAskedFor(
        _ row: (query: String, includingCacheOnly: Bool, expected: [String])
    ) {
        let websites = ManagedWebsites.grouping(
            [
                WebsiteDataRecord(displayName: "cdn.net", kinds: [.cache]),
                WebsiteDataRecord(displayName: "google.com", kinds: [.cookies, .cache]),
                // Cache only, but an exception keeps it in view: there is a permission to manage.
                WebsiteDataRecord(displayName: "zoom.us", kinds: [.cache]),
            ],
            exceptionsIn: config(camera: [("zoom.us", .allow), ("example.com", .deny)]))

        #expect(ManagedWebsites.cacheOnlyCount(websites) == 1)
        #expect(
            ManagedWebsites.filtered(websites, matching: row.query, includingCacheOnly: row.includingCacheOnly)
                .map(\.domain) == row.expected)
    }
}
