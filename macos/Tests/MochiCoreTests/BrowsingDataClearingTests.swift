import Foundation
import Testing

@testable import MochiCore

/// 清除浏览数据… (#107): the pure pieces — where a time range starts, which website data each
/// ticked kind stands for, and what that comes to in WebKit's own data types.
@Suite struct BrowsingDataClearingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [
        (range: BrowsingDataTimeRange.pastHour, seconds: 3_600.0),
        (range: .past24Hours, seconds: 86_400),
        (range: .past7Days, seconds: 7 * 86_400),
        (range: .past4Weeks, seconds: 28 * 86_400),
    ])
    func aBoundedRangeStartsThatLongBeforeNow(_ row: (range: BrowsingDataTimeRange, seconds: Double)) {
        #expect(row.range.startDate(now: now) == now.addingTimeInterval(-row.seconds))
    }

    @Test func allTimeStartsAtTheDistantPast() {
        #expect(BrowsingDataTimeRange.allTime.startDate(now: now) == .distantPast)
    }

    @Test func theRangesAreOfferedShortestFirstAndDefaultToAllTime() {
        #expect(BrowsingDataTimeRange.allCases == [.pastHour, .past24Hours, .past7Days, .past4Weeks, .allTime])
        #expect(BrowsingDataTimeRange.defaultRange == .allTime)
        #expect(BrowsingDataTimeRange.allCases.map(\.displayName)
            == ["过去 1 小时", "过去 24 小时", "过去 7 天", "过去 4 周", "时间不限"])
    }

    @Test func historyCookiesAndCacheAreTickedByDefaultButPagePermissionExceptionsAreNot() {
        #expect(BrowsingDataKind.defaultSelection == [.history, .websiteData, .cache])
        #expect(BrowsingDataKind.allCases.map(\.displayName)
            == ["历史记录", "Cookie 和网站数据", "缓存的图片和文件", "网页权限例外"])
    }

    @Test(arguments: [
        (kinds: [BrowsingDataKind](), categories: [WebsiteDataCategory]()),
        (kinds: [.cache], categories: [.cache]),
        (kinds: [.websiteData], categories: [.cookiesAndOtherData]),
        (kinds: [.websiteData, .cache], categories: [.cookiesAndOtherData, .cache]),
        (kinds: [.pagePermissionExceptions], categories: []),
        (kinds: [.cache, .pagePermissionExceptions], categories: [.cache]),
        (kinds: [.history], categories: []),
        (kinds: [.history, .websiteData], categories: [.cookiesAndOtherData]),
    ])
    func eachKindStandsForItsOwnWebsiteData(
        _ row: (kinds: [BrowsingDataKind], categories: [WebsiteDataCategory])
    ) {
        #expect(BrowsingDataKind.websiteDataCategories(for: Set(row.kinds)) == Set(row.categories))
    }

    // MARK: - WebKit data types

    private let allTypes: Set<String> = [
        "WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache", "WKWebsiteDataTypeCookies",
        "WKWebsiteDataTypeLocalStorage", "WKWebsiteDataTypeIndexedDBDatabases", "WKWebsiteDataTypeFetchCache",
    ]

    @Test func theCacheIsWebKitsDiskAndMemoryCacheOnly() {
        #expect(WebsiteDataCategory.webKitTypes(for: [.cache], among: allTypes)
            == ["WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache"])
    }

    @Test func cookiesAndOtherDataIsEveryOtherType() {
        #expect(WebsiteDataCategory.webKitTypes(for: [.cookiesAndOtherData], among: allTypes)
            == allTypes.subtracting(["WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache"]))
    }

    @Test func bothTogetherAreEveryType() {
        #expect(WebsiteDataCategory.webKitTypes(for: [.cache, .cookiesAndOtherData], among: allTypes) == allTypes)
        #expect(WebsiteDataCategory.webKitTypes(for: [], among: allTypes).isEmpty)
    }

    /// The constants this mapping names are WebKit's real ones, and both caches are among the
    /// types WebKit itself reports.
    @Test func theCacheTypesAreAmongWebKitsOwn() {
        let real = WebsiteDataCategory.allWebKitTypes
        #expect(WebsiteDataCategory.webKitTypes(for: [.cache], among: real).count == 2)
        #expect(WebsiteDataCategory.webKitTypes(for: [.cookiesAndOtherData], among: real).contains("WKWebsiteDataTypeCookies"))
    }
}
