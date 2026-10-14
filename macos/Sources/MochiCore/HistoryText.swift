import Foundation

/// How history is put into words, shared by the 历史记录 menu (#102) and window (#108) so a page
/// and a day read the same in both.
enum HistoryText {
    /// 「10月11日 星期日」 — a day in this year.
    static let dayFormat = "M月d日 EEEE"
    /// 「2025年10月11日 星期六」 — a day in another year.
    static let dayWithYearFormat = "yyyy年M月d日 EEEE"

    /// A Chinese-locale formatter for `format`, in `calendar` and its time zone — the calendar
    /// the store groups days by.
    static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }

    /// The page's title on one line — runs of whitespace, line breaks included, become one
    /// space — or `nil` when it has none worth showing.
    static func title(of visit: HistoryVisit) -> String? {
        let title = (visit.title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : title
    }
}
