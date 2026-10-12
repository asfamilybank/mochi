import Foundation

/// 隐私与安全性 → 移除历史记录项目 (#110), Safari's choices: how long a page stays in the history
/// after its last visit. Applied at launch, when the setting changes, and when the 历史记录 window
/// opens — 手动 never removes anything by itself.
public enum HistoryRetention: String, CaseIterable, Sendable {
    case oneDay = "one_day"
    case oneWeek = "one_week"
    case twoWeeks = "two_weeks"
    case oneMonth = "one_month"
    case oneYear = "one_year"
    case manual

    public static let defaultRetention: HistoryRetention = .oneYear

    public var displayName: String {
        switch self {
        case .oneDay: "一天后"
        case .oneWeek: "一周后"
        case .twoWeeks: "两周后"
        case .oneMonth: "一个月后"
        case .oneYear: "一年后"
        case .manual: "手动"
        }
    }

    /// The oldest last-visited time that is kept — anything visited before it has expired — or
    /// `nil` for 手动. Counted back in `calendar`, so a month is a calendar month.
    public func cutoff(now: Date, calendar: Calendar) -> Date? {
        let period: (component: Calendar.Component, value: Int)
        switch self {
        case .oneDay: period = (.day, 1)
        case .oneWeek: period = (.day, 7)
        case .twoWeeks: period = (.day, 14)
        case .oneMonth: period = (.month, 1)
        case .oneYear: period = (.year, 1)
        case .manual: return nil
        }
        return calendar.date(byAdding: period.component, value: -period.value, to: now)
    }
}

extension HistoryStore {
    /// Removes every entry `retention` has expired, at the store's own "now" and calendar.
    public func removeEntries(olderThan retention: HistoryRetention) {
        guard let cutoff = retention.cutoff(now: now(), calendar: calendar) else { return }
        removeEntries(visitedBefore: cutoff)
    }
}
