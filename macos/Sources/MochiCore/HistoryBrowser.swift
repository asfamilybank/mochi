import Foundation

/// What the 历史记录 window (#108) shows and does, kept out of the view so it can be tested
/// against a real store: the visits grouped by day, newest first, narrowed by a search over
/// titles and addresses; deleting visits or a whole day; and opening a page in the widget.
/// A row is one visit (#114): a page visited three times is three rows.
///
/// Stateless over the store — every call reads it afresh at the store's own "now" and calendar,
/// so the window, the 历史记录 menu and recording all see the same history, and 今天 is the day
/// the store groups by.
public final class HistoryBrowser {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: HistoryVisit.ID
        public let url: URL
        /// The page's title on one line, or its address when it has none.
        public let title: String
        /// The address, under a title — `nil` when the address already is the title.
        public let subtitle: String?
        /// When it was visited, `HH:mm`.
        public let time: String

        public init(id: HistoryVisit.ID, url: URL, title: String, subtitle: String?, time: String) {
            self.id = id
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
    ///     `removeExpiredVisits()`. 手动 unless given.
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
    public func removeExpiredVisits() {
        store.removeVisits(olderThan: retention())
    }

    /// Everything whose title or address contains `query` (case-insensitively, surrounding
    /// whitespace ignored), one section per day that has any.
    public func sections(matching query: String) -> [Section] {
        let visits = store.search(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return Self.sections(of: visits, now: store.now(), calendar: store.calendar)
    }

    /// Only these visits — other visits to the same pages stay.
    public func delete(_ visits: Set<HistoryVisit.ID>) {
        store.deleteVisits(visits)
    }

    /// 删除这一天 — every visit that day, searched for or not.
    public func deleteDay(_ day: Date) {
        store.deleteDay(containing: day)
    }

    /// A double-click. There is one widget, so of several selected pages only the topmost (as
    /// `sections` lists them) is opened; a selection that is no longer shown opens nothing.
    public func open(_ selection: Set<HistoryVisit.ID>, shownIn sections: [Section]) {
        guard let url = sections.lazy.flatMap(\.rows).first(where: { selection.contains($0.id) })?.url else { return }
        openInWidget(url)
    }

    // MARK: - Grouping

    /// - Parameter visits: newest first, as `HistoryStore` returns them.
    static func sections(of visits: [HistoryVisit], now: Date, calendar: Calendar) -> [Section] {
        var days: [(day: Date, rows: [Row])] = []
        let time = HistoryText.formatter("HH:mm", calendar: calendar)
        for visit in visits {
            let day = calendar.startOfDay(for: visit.visitedAt)
            if days.last?.day != day { days.append((day, [])) }
            days[days.count - 1].rows.append(row(for: visit, time: time))
        }
        return days.map { Section(day: $0.day, title: title(of: $0.day, now: now, calendar: calendar), rows: $0.rows) }
    }

    private static func row(for visit: HistoryVisit, time: DateFormatter) -> Row {
        let title = HistoryText.title(of: visit)
        let address = visit.url.absoluteString
        return Row(
            id: visit.id, url: visit.url, title: title ?? address, subtitle: title == nil ? nil : address,
            time: time.string(from: visit.visitedAt))
    }

    private static func title(of day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday { return "昨天" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let format = sameYear ? HistoryText.dayFormat : HistoryText.dayWithYearFormat
        return HistoryText.formatter(format, calendar: calendar).string(from: day)
    }
}
