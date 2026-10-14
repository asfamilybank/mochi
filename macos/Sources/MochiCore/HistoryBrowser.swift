import Foundation

/// The 历史记录 window's state and what it does (#108), kept out of the view so it can be tested
/// against a real store. The SwiftUI view only draws it.
///
/// Two modes, by whether the search query (surrounding whitespace ignored) is empty:
/// - the **timeline** (#116): one foldable day per day that has visits, newest first, with how
///   many visits it has. Only an expanded day's visits are read — a year of history opens as fast
///   as a week of it.
/// - **search** (#118): the visits whose title or address contains the query, as one flat
///   timeline across every day, folded or not — each row saying which day as well as when — and
///   how many there are. A leading `site:<host>` narrows them to that host exactly.
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
        /// When it was visited: `HH:mm` under its day's header; in search results, which have no
        /// headers, the day's title before it — 「今天 · 10月14日 星期三 14:32」.
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

    private let store: HistoryStore
    private let openInWidget: (URL) -> Void
    private let retention: () -> HistoryRetention

    /// As typed, surrounding whitespace and all.
    public private(set) var query = ""
    /// The timeline — empty while searching.
    public private(set) var days: [Day] = []
    /// The search results, newest first — empty while not searching.
    public private(set) var results: [Row] = []

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

    /// What a search is narrowed by (#118).
    public struct SearchTerms: Equatable, Sendable {
        /// The `site:` host, lowercased — `nil` without one.
        public let host: String?
        /// The keywords: everything else.
        public let text: String

        public init(host: String?, text: String) {
            self.host = host
            self.text = text
        }
    }

    public var searchTerms: SearchTerms {
        Self.parse(trimmedQuery)
    }

    /// 「N 个匹配项」.
    public var matchCount: Int {
        results.count
    }

    /// Every row on show, top to bottom.
    public var shownRows: [Row] {
        isSearching ? results : days.flatMap(\.rows)
    }

    /// #110: called as the window opens, before it lists anything, so nothing past the retention
    /// is ever shown.
    public func removeExpiredVisits() {
        store.removeVisits(olderThan: retention())
    }

    /// Re-reads the store, keeping which days are unfolded — searching leaves them alone, so the
    /// timeline comes back as it was. Once 今天 has moved on (the window was open across midnight),
    /// the new 今天 is unfolded too.
    public func reload() {
        let now = store.now()
        let today = store.calendar.startOfDay(for: now)
        if let previous = self.today, previous != today { expandedDays.insert(today) }
        self.today = today
        let time = HistoryText.formatter("HH:mm", calendar: store.calendar)
        if isSearching {
            days = []
            let terms = Self.parse(trimmedQuery)
            var dayTitles: [Date: String] = [:]
            results = store.search(terms.text, host: terms.host).map { visit in
                let day = store.calendar.startOfDay(for: visit.visitedAt)
                if dayTitles[day] == nil { dayTitles[day] = Self.title(of: day, now: now, calendar: store.calendar) }
                return Self.row(for: visit, time: time, day: dayTitles[day])
            }
        } else {
            results = []
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

    /// 拷贝 (⌘C, #119): the selected visit's whole address — only for one row on show; several
    /// selected, nothing is copied.
    public func copiedText(for selection: Set<HistoryVisit.ID>) -> String? {
        onlyRow(of: selection)?.url.absoluteString
    }

    /// 显示此网站的所有记录 (#119): the search for every visit to the selected visit's host — only
    /// for one row on show.
    public func siteQuery(for selection: Set<HistoryVisit.ID>) -> String? {
        guard let host = onlyRow(of: selection)?.url.host?.lowercased() else { return nil }
        return "site:\(host)"
    }

    private func onlyRow(of selection: Set<HistoryVisit.ID>) -> Row? {
        guard selection.count == 1 else { return nil }
        return shownRows.first { selection.contains($0.id) }
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

    /// A leading `site:<host>` (any case) and the keywords after it; the whole query as keywords
    /// otherwise. A host pasted with its scheme or path counts as its host.
    static func parse(_ query: String) -> SearchTerms {
        let prefix = "site:"
        guard query.lowercased().hasPrefix(prefix) else { return SearchTerms(host: nil, text: query) }
        let rest = query.dropFirst(prefix.count)
        let token = String(rest.prefix { !$0.isWhitespace })
        guard !token.isEmpty else { return SearchTerms(host: nil, text: query) }
        let text = rest.dropFirst(token.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let address = token.contains("://") ? token : "https://\(token)"
        let host = URL(string: address)?.host ?? token
        return SearchTerms(host: host.lowercased(), text: text)
    }

    /// - Parameter day: the day's title, for a row with no day header above it (search results).
    private static func row(for visit: HistoryVisit, time: DateFormatter, day: String? = nil) -> Row {
        let title = HistoryText.title(of: visit)
        let address = visit.url.absoluteString
        let clock = time.string(from: visit.visitedAt)
        return Row(
            id: visit.id, url: visit.url, title: title ?? address, subtitle: title == nil ? nil : address,
            time: day.map { "\($0) \(clock)" } ?? clock, faviconID: visit.faviconID)
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
