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
        "WKWebsiteDataTypeOfflineWebApplicationCache",
    ]

    private let cacheTypes: Set<String> = [
        "WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache", "WKWebsiteDataTypeFetchCache",
        "WKWebsiteDataTypeOfflineWebApplicationCache",
    ]

    @Test func theCacheIsEveryWebKitCache() {
        #expect(WebsiteDataCategory.webKitTypes(for: [.cache], among: allTypes) == cacheTypes)
    }

    @Test func cookiesAndOtherDataIsEveryOtherType() {
        #expect(WebsiteDataCategory.webKitTypes(for: [.cookiesAndOtherData], among: allTypes)
            == allTypes.subtracting(cacheTypes))
    }

    @Test func bothTogetherAreEveryType() {
        #expect(WebsiteDataCategory.webKitTypes(for: [.cache, .cookiesAndOtherData], among: allTypes) == allTypes)
        #expect(WebsiteDataCategory.webKitTypes(for: [], among: allTypes).isEmpty)
    }

    /// 清除浏览数据's 「缓存的图片和文件」 clears exactly what 管理网站和数据… lists as 缓存 — the two
    /// read the same mapping.
    @Test(arguments: [
        (type: "WKWebsiteDataTypeDiskCache", kind: WebsiteDataKind.cache),
        (type: "WKWebsiteDataTypeMemoryCache", kind: .cache),
        (type: "WKWebsiteDataTypeFetchCache", kind: .cache),
        (type: "WKWebsiteDataTypeOfflineWebApplicationCache", kind: .cache),
        (type: "WKWebsiteDataTypeCookies", kind: .cookies),
        (type: "WKWebsiteDataTypeSessionStorage", kind: .localStorage),
        (type: "WKWebsiteDataTypeIndexedDBDatabases", kind: .databases),
        (type: "WKWebsiteDataTypeServiceWorkerRegistrations", kind: .serviceWorkers),
        (type: "WKWebsiteDataTypeSomethingNew", kind: .other),
    ])
    func eachWebKitTypeFoldsIntoOneKind(_ row: (type: String, kind: WebsiteDataKind)) {
        #expect(WebsiteDataKind(webKitType: row.type) == row.kind)
        let category: WebsiteDataCategory = row.kind == .cache ? .cache : .cookiesAndOtherData
        #expect(WebsiteDataCategory.webKitTypes(for: [category], among: [row.type]) == [row.type])
    }

    /// The constants this mapping names are WebKit's real ones, and the disk and memory caches are
    /// among the types WebKit itself reports.
    @Test func theCacheTypesAreAmongWebKitsOwn() {
        let real = WebsiteDataCategory.allWebKitTypes
        let caches = WebsiteDataCategory.webKitTypes(for: [.cache], among: real)
        #expect(caches.isSuperset(of: ["WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache"]))
        #expect(caches.isSubset(of: cacheTypes))
        #expect(WebsiteDataCategory.webKitTypes(for: [.cookiesAndOtherData], among: real).contains("WKWebsiteDataTypeCookies"))
    }
}
