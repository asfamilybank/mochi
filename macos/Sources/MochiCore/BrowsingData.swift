import Foundation
import WebKit

/// 清除浏览数据…'s 时间范围 (#107): how far back to clear, counted back from the moment of the
/// click. Fixed lengths rather than calendar days, after Chrome's 删除浏览数据.
public enum BrowsingDataTimeRange: String, CaseIterable, Sendable {
    case pastHour
    case past24Hours
    case past7Days
    case past4Weeks
    case allTime

    public static let defaultRange: BrowsingDataTimeRange = .allTime

    public var displayName: String {
        switch self {
        case .pastHour: "过去 1 小时"
        case .past24Hours: "过去 24 小时"
        case .past7Days: "过去 7 天"
        case .past4Weeks: "过去 4 周"
        case .allTime: "时间不限"
        }
    }

    /// The earliest modification time that is cleared; anything modified at or after it goes.
    public func startDate(now: Date) -> Date {
        let hour: TimeInterval = 3_600
        switch self {
        case .pastHour: return now.addingTimeInterval(-hour)
        case .past24Hours: return now.addingTimeInterval(-24 * hour)
        case .past7Days: return now.addingTimeInterval(-7 * 24 * hour)
        case .past4Weeks: return now.addingTimeInterval(-28 * 24 * hour)
        case .allTime: return .distantPast
        }
    }
}

/// One tickable kind of 浏览数据 (#107). 历史记录 (#110) lives in `HistoryStore`, the next two are
/// 网站数据 (WebKit's), and the exceptions live in `config.toml` — `SettingsController
/// .clearBrowsingData` is the one place that says what clearing each kind means.
public enum BrowsingDataKind: String, CaseIterable, Sendable {
    case history
    case websiteData
    case cache
    case pagePermissionExceptions

    /// History and the two kinds of website data are on by default — logging out of every site is
    /// what clearing them costs, which the sheet says; the exceptions are choices the user made
    /// deliberately and stay unless asked for.
    public static let defaultSelection: Set<BrowsingDataKind> = [.history, .websiteData, .cache]

    public var displayName: String {
        switch self {
        case .history: "历史记录"
        case .websiteData: "Cookie 和网站数据"
        case .cache: "缓存的图片和文件"
        case .pagePermissionExceptions: "网页权限例外"
        }
    }

    /// The website data `kinds` stand for — empty when none of them is website data, in which
    /// case the platform isn't asked to remove anything.
    public static func websiteDataCategories(for kinds: Set<BrowsingDataKind>) -> Set<WebsiteDataCategory> {
        Set(kinds.compactMap { kind in
            switch kind {
            case .websiteData: .cookiesAndOtherData
            case .cache: .cache
            case .history, .pagePermissionExceptions: nil
            }
        })
    }
}

/// How 清除浏览数据 splits WebKit's website data (#107): the HTTP cache, which can go without
/// logging anyone out, and everything else.
public enum WebsiteDataCategory: String, CaseIterable, Sendable {
    /// WebKit's disk and memory caches.
    case cache
    /// Every other website data type: cookies, local and session storage, IndexedDB, service
    /// workers and their caches, ….
    case cookiesAndOtherData

    static let cacheWebKitTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]

    /// Every type the running WebKit knows about.
    static var allWebKitTypes: Set<String> { WKWebsiteDataStore.allWebsiteDataTypes() }

    /// The WebKit data types `categories` come to, out of `all` (normally `allWebKitTypes`;
    /// passed in so the split is testable without WebKit's list).
    static func webKitTypes(for categories: Set<WebsiteDataCategory>, among all: Set<String>) -> Set<String> {
        var types: Set<String> = []
        if categories.contains(.cache) { types.formUnion(all.intersection(cacheWebKitTypes)) }
        if categories.contains(.cookiesAndOtherData) { types.formUnion(all.subtracting(cacheWebKitTypes)) }
        return types
    }
}
