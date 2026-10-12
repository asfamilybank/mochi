import Foundation

/// What the main menu's 历史记录 lists below 返回/前进 (#102) — a pure function of the entries and
/// "now", rebuilt every time the menu is about to open: today's most recent pages, then one
/// submenu for each of the past six days that has any.
public struct HistoryMenu: Equatable {
    public struct Item: Equatable {
        public let title: String
        public let url: URL
    }

    public struct Day: Equatable {
        /// The start of the day.
        public let day: Date
        public let title: String
        public let items: [Item]
    }

    public static let todayLimit = 15
    public static let dayLimit = 30
    /// Days before today that can get a submenu.
    public static let earlierDayCount = 6
    /// A menu item grows as wide as its title; past this many characters it is cut short.
    public static let maximumTitleLength = 60

    public let today: [Item]
    public let earlierDays: [Day]

    /// The start of the oldest day the menu can show — everything since then is what `build`
    /// needs to be given.
    public static func earliestDay(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -earlierDayCount, to: today) ?? today
    }

    /// - Parameter entries: newest first, as `HistoryStore` returns them; anything older than
    ///   `earliestDay` or later than today is left out.
    public static func build(entries: [HistoryEntry], now: Date, calendar: Calendar) -> HistoryMenu {
        let today = calendar.startOfDay(for: now)
        let earliest = earliestDay(now: now, calendar: calendar)
        var todayItems: [Item] = []
        var days: [(day: Date, items: [Item])] = []
        for entry in entries.sorted(by: { $0.lastVisited > $1.lastVisited }) {
            let day = calendar.startOfDay(for: entry.lastVisited)
            if day == today {
                if todayItems.count < todayLimit { todayItems.append(item(for: entry)) }
            } else if day < today, day >= earliest {
                if days.last?.day != day { days.append((day, [])) }
                if days[days.count - 1].items.count < dayLimit {
                    days[days.count - 1].items.append(item(for: entry))
                }
            }
        }
        return HistoryMenu(
            today: todayItems,
            earlierDays: days.map { Day(day: $0.day, title: title(of: $0.day, calendar: calendar), items: $0.items) })
    }

    /// The page's title on one line, or its address when it has none; cut to
    /// `maximumTitleLength` with a trailing ellipsis.
    private static func item(for entry: HistoryEntry) -> Item {
        let title = (entry.title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let shown = title.isEmpty ? entry.url.absoluteString : title
        let cut = shown.count > maximumTitleLength ? shown.prefix(maximumTitleLength - 1) + "…" : shown
        return Item(title: String(cut), url: entry.url)
    }

    /// 「10月11日 星期日」.
    private static func title(of day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: day)
    }
}
