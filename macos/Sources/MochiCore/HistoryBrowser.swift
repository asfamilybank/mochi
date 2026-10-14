import Foundation

/// The 历史记录 window's state and what it does (#108), kept out of the view so it can be tested
/// against a real store. The SwiftUI view only draws it.
///
/// Two modes, by whether the search query (surrounding whitespace ignored) is empty:
/// - the **timeline** (#116): one foldable day per day that has visits, newest first, with how
///   many visits it has. Only an expanded day's visits are read — a year of history opens as fast
///   as a week of it.
/// - **search**: the visits whose title or address contains the query, one section per day.
///
/// A row is one visit (#114): a page visited three times is three rows. Deleting visits or a whole
/// day and opening a page in the widget go through here too.
///
/// "Now" and the calendar are the store's, so 今天 is the day the store groups by.
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
        /// The visit's site icon (#117), for `HistoryBrowser.favicon(_:)`.
        public let faviconID: String?

        public init(
            id: HistoryVisit.ID, url: URL, title: String, subtitle: String?, time: String, faviconID: String? = nil
        ) {
            self.id = id
            self.faviconID = faviconID
            self.url = url
            self.title = title
            self.subtitle = subtitle
            self.time = time
        }
    }

    /// One day of the timeline (#116).
    public struct Day: Equatable, Identifiable, Sendable {
        public var id: Date { day }
        /// The start of the day.
        public let day: Date
        /// 「今天 · 10月14日 星期三」「昨天 · 10月13日 星期二」「10月4日 星期日」, with the year when it
        /// isn't this one.
        public let title: String
        /// How many visits it has, folded or not — the 「N 项」.
        public let visits: Int
        public let isExpanded: Bool
        /// The day's visits, newest first — empty while folded: a folded day's visits aren't read.
        public let rows: [Row]
    }

    /// One day of search results.
    public struct Section: Equatable, Identifiable, Sendable {
        public var id: Date { day }
        /// The start of the day.
        public let day: Date
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

    /// As typed, surrounding whitespace and all.
    public private(set) var query = ""
    /// The timeline — empty while searching.
    public private(set) var days: [Day] = []
    /// The search results — empty while not searching.
    public private(set) var sections: [Section] = []

    /// The days unfolded. Starts empty, everything folded, until `resetExpansion()`.
    private var expandedDays: Set<Date> = []
    /// 今天 as of the last read, so a read past midnight can tell a new day has begun.
    private var today: Date?

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

    public var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// Every row on show, top to bottom.
    public var shownRows: [Row] {
        isSearching ? sections.flatMap(\.rows) : days.flatMap(\.rows)
    }

    /// #110: called as the window opens, before it lists anything, so nothing past the retention
    /// is ever shown.
    public func removeExpiredVisits() {
        store.removeVisits(olderThan: retention())
    }

    /// Re-reads the store, keeping which days are unfolded. Once 今天 has moved on (the window was
    /// open across midnight), the new 今天 is unfolded too.
    public func reload() {
        let now = store.now()
        let today = store.calendar.startOfDay(for: now)
        if let previous = self.today, previous != today { expandedDays.insert(today) }
        self.today = today
        if isSearching {
            days = []
            sections = Self.sections(of: store.search(trimmedQuery), now: now, calendar: store.calendar)
        } else {
            sections = []
            let time = HistoryText.formatter("HH:mm", calendar: store.calendar)
            days = store.dayCounts().map { count in
                let isExpanded = expandedDays.contains(count.day)
                return Day(
                    day: count.day, title: Self.title(of: count.day, now: now, calendar: store.calendar),
                    visits: count.visits, isExpanded: isExpanded,
                    rows: isExpanded ? store.visits(onDayOf: count.day).map { Self.row(for: $0, time: time) } : [])
            }
        }
    }

    /// Folds every day but 今天 — what the window shows each time ⌘Y opens it.
    public func resetExpansion() {
        let today = store.calendar.startOfDay(for: store.now())
        expandedDays = [today]
        self.today = today
        reload()
    }

    public func setExpanded(_ isExpanded: Bool, day: Date) {
        if isExpanded { expandedDays.insert(day) } else { expandedDays.remove(day) }
        reload()
    }

    public func search(_ query: String) {
        self.query = query
        reload()
    }

    /// The PNG behind a row's `faviconID` (#117) — read from the store, never fetched: opening the
    /// window makes no network request.
    public func favicon(_ id: String) -> Data? {
        store.favicon(id)
    }

    /// Only these visits — other visits to the same pages stay.
    public func delete(_ visits: Set<HistoryVisit.ID>) {
        store.deleteVisits(visits)
        reload()
    }

    /// 删除这一天 — every visit that day, searched for or not.
    public func deleteDay(_ day: Date) {
        store.deleteDay(containing: day)
        reload()
    }

    /// A double-click. There is one widget, so of several selected visits only the topmost on show
    /// is opened; a selection that is no longer shown opens nothing.
    public func open(_ selection: Set<HistoryVisit.ID>) {
        guard let url = shownRows.first(where: { selection.contains($0.id) })?.url else { return }
        openInWidget(url)
    }

    // MARK: - Rows and titles

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            time: time.string(from: visit.visitedAt), faviconID: visit.faviconID)
    }

    private static func title(of day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let format = sameYear ? HistoryText.dayFormat : HistoryText.dayWithYearFormat
        let date = HistoryText.formatter(format, calendar: calendar).string(from: day)
        if day == today { return "今天 · \(date)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday {
            return "昨天 · \(date)"
        }
        return date
    }
}
