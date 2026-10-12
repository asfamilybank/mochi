import Foundation

/// What the 历史记录 window (#108) shows and does, kept out of the view so it can be tested
/// against a real store: the history grouped by day, newest first, narrowed by a search over
/// titles and addresses; deleting pages or a whole day; and opening a page in the widget.
///
/// Stateless over the store — every call reads it afresh at the store's own "now" and calendar,
/// so the window, the 历史记录 menu and recording all see the same history, and 今天 is the day
/// the store groups by.
public final class HistoryBrowser {
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        /// The page's title on one line, or its address when it has none.
        public let title: String
        /// The address, under a title — `nil` when the address already is the title.
        public let subtitle: String?
        /// When it was last visited, `HH:mm`.
        public let time: String

        public init(url: URL, title: String, subtitle: String?, time: String) {
            self.url = url
            self.title = title
            self.subtitle = subtitle
            self.time = time
        }
    }

    public struct Section: Equatable, Identifiable, Sendable {
        public var id: Date { day }
        /// The start of the day.
        public let day: Date
        /// 「今天」「昨天」「10月10日 星期六」, with the year when it isn't this one.
        public let title: String
        public let rows: [Row]

        public init(day: Date, title: String, rows: [Row]) {
            self.day = day
            self.title = title
            self.rows = rows
        }
    }

    private let store: HistoryStore
    private let openInWidget: (URL) -> Void
    private let retention: () -> HistoryRetention

    /// - Parameters:
    ///   - retention: 移除历史记录项目 as configured right now (#110) — read, not cached, at each
    ///     `removeExpiredEntries()`. 手动 unless given.
    ///   - open: `Orchestrator.openFromHistory` — reopens a closed widget, leaves Ghost Mode alone.
    public init(
        store: HistoryStore, retention: @escaping () -> HistoryRetention = { .manual },
        open: @escaping (URL) -> Void
    ) {
        self.store = store
        self.retention = retention
        self.openInWidget = open
    }

    /// #110: called as the window opens, before it lists anything, so nothing past the retention
    /// is ever shown.
    public func removeExpiredEntries() {
        store.removeEntries(olderThan: retention())
    }

    /// Everything whose title or address contains `query` (case-insensitively, surrounding
    /// whitespace ignored), one section per day that has any.
    public func sections(matching query: String) -> [Section] {
        let entries = store.search(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return Self.sections(of: entries, now: store.now(), calendar: store.calendar)
    }

    public func delete(_ urls: Set<URL>) {
        store.deleteEntries(for: Array(urls))
    }

    /// 删除这一天 — every page last visited that day, searched for or not.
    public func deleteDay(_ day: Date) {
        store.deleteDay(containing: day)
    }

    /// A double-click. There is one widget, so of several selected pages only the topmost (as
    /// `sections` lists them) is opened; a selection that is no longer shown opens nothing.
    public func open(_ selection: Set<URL>, shownIn sections: [Section]) {
        guard let url = sections.lazy.flatMap(\.rows).first(where: { selection.contains($0.url) })?.url else { return }
        openInWidget(url)
    }

    // MARK: - Grouping

    /// - Parameter entries: newest first, as `HistoryStore` returns them.
    static func sections(of entries: [HistoryEntry], now: Date, calendar: Calendar) -> [Section] {
        var days: [(day: Date, rows: [Row])] = []
        let time = formatter("HH:mm", calendar: calendar)
        for entry in entries {
            let day = calendar.startOfDay(for: entry.lastVisited)
            if days.last?.day != day { days.append((day, [])) }
            days[days.count - 1].rows.append(row(for: entry, time: time))
        }
        return days.map { Section(day: $0.day, title: title(of: $0.day, now: now, calendar: calendar), rows: $0.rows) }
    }

    private static func row(for entry: HistoryEntry, time: DateFormatter) -> Row {
        let title = (entry.title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let address = entry.url.absoluteString
        return Row(
            url: entry.url, title: title.isEmpty ? address : title, subtitle: title.isEmpty ? nil : address,
            time: time.string(from: entry.lastVisited))
    }

    private static func title(of day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return "昨天" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return formatter(sameYear ? "M月d日 EEEE" : "yyyy年M月d日 EEEE", calendar: calendar).string(from: day)
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }
}
