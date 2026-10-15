import CryptoKit
import Foundation

/// One visit in the history (`CONTEXT.md`「历史记录」, ADR-0030): the widget's main page arriving at
/// an address, at a moment, under the title and site icon the page had then. Visiting the same
/// address again is another visit — history is a timeline, not a list of addresses.
public struct HistoryVisit: Equatable, Identifiable, Sendable {
    public typealias ID = Int64

    public let id: ID
    public let url: URL
    /// `nil` until the page reports one.
    public let title: String?
    public let visitedAt: Date
    /// The site icon the visit was made under (#117) — a key for `HistoryStore.favicon(_:)`,
    /// `nil` when none came. Visits whose icons are the same bytes share one.
    public let faviconID: String?

    public init(id: ID, url: URL, title: String?, visitedAt: Date, faviconID: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
        self.faviconID = faviconID
    }
}

/// A calendar day that has visits, and how many (#116) — all a folded day in the 历史记录 window
/// shows.
public struct HistoryDayCount: Equatable, Sendable {
    /// The start of the day.
    public let day: Date
    public let visits: Int

    public init(day: Date, visits: Int) {
        self.day = day
        self.visits = visits
    }
}

/// Mochi's history, kept in SQLite (`Application Support/Mochi/History.db`) through the system's
/// own `libsqlite3` — no dependency added (#102). The interface is shaped by what the app does with
/// history; no SQL leaks out.
///
/// Append-only, one row per visit (#114, ADR-0030): every change of the widget's main-page address
/// adds a row, and what a visit was titled is written to that row alone. The address is stored
/// minus its `#` fragment (a fragment only points somewhere inside the same page).
///
/// Each visit's site icon (#117) is kept apart, once per distinct PNG (keyed by its SHA-256), so a
/// year of visits to one site is one copy of its icon. An icon goes as soon as no visit shows it.
///
/// "Now" and the calendar that decides where one day ends and the next begins are injected, so
/// day grouping can be tested across midnight without waiting for one.
///
/// A database that can't be used never blocks launch: `SQLiteDatabase` moves only a damaged file
/// aside, and otherwise keeps this session's history in memory.
///
/// There is no migration: a file from when history kept one row per address keeps that old table,
/// unread, beside the timeline.
///
/// Main thread only, like everything else that touches it.
public final class HistoryStore {
    public let now: () -> Date
    public let calendar: Calendar
    private let db: SQLiteDatabase

    /// `Application Support/Mochi/History.db`, next to `config.toml`.
    public static var defaultDatabaseURL: URL {
        WidgetConfig.defaultConfigURL.deletingLastPathComponent().appendingPathComponent("History.db")
    }

    private static let schema = """
        CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY,
            url TEXT NOT NULL,
            host TEXT,
            title TEXT,
            visited_at REAL NOT NULL,
            favicon_hash TEXT
        );
        CREATE INDEX IF NOT EXISTS visits_visited_at ON visits (visited_at);
        CREATE INDEX IF NOT EXISTS visits_favicon_hash ON visits (favicon_hash);
        CREATE INDEX IF NOT EXISTS visits_host ON visits (host, visited_at);
        CREATE TABLE IF NOT EXISTS favicons (
            hash TEXT PRIMARY KEY NOT NULL,
            png BLOB NOT NULL
        );
        PRAGMA user_version = 2;
        """

    /// - Parameters:
    ///   - databaseURL: the database file, created along with its folder when missing; `nil`
    ///     keeps the history in memory (tests).
    ///   - busyTimeout: how long to wait for another connection's lock before giving up on the
    ///     file for this session.
    public init(
        databaseURL: URL?, now: @escaping () -> Date = Date.init, calendar: Calendar = .current,
        busyTimeout: TimeInterval = 2
    ) {
        self.now = now
        self.calendar = calendar
        db = SQLiteDatabase(databaseURL: databaseURL, schema: Self.schema, busyTimeout: busyTimeout)
    }

    // MARK: Recording

    /// Records one visit to `url` at the injected "now", made under `favicon` (a PNG) when one is
    /// already known, returning it for its title and icon to be written to — `nil` only when the
    /// database refused the row.
    @discardableResult
    public func recordVisit(to url: URL, favicon: Data? = nil) -> HistoryVisit.ID? {
        let faviconID = favicon.flatMap(storeFavicon)
        guard
            db.execute(
                "INSERT INTO visits (url, host, title, visited_at, favicon_hash) VALUES (?1, ?2, NULL, ?3, ?4)",
                .text(Self.address(of: url)), url.host.map { .text($0.lowercased()) } ?? .null,
                .real(now().timeIntervalSinceReferenceDate), faviconID.map(SQLiteDatabase.Value.text) ?? .null)
        else { return nil }
        return db.lastInsertRowID
    }

    /// Sets the site icon of one visit (a PNG) — for an icon that arrives after the visit was
    /// recorded. Does nothing for a visit that isn't (or is no longer) recorded.
    public func updateFavicon(_ png: Data, ofVisit id: HistoryVisit.ID) {
        guard let faviconID = storeFavicon(png) else { return }
        db.execute("UPDATE visits SET favicon_hash = ?1 WHERE id = ?2", .text(faviconID), .integer(id))
        removeUnshownFavicons()
    }

    /// Sets the title of one visit — the last title a page reports while it is up is the one kept.
    /// Does nothing for a visit that isn't (or is no longer) recorded.
    public func updateTitle(_ title: String, ofVisit id: HistoryVisit.ID) {
        db.execute("UPDATE visits SET title = ?1 WHERE id = ?2", .text(title), .integer(id))
    }

    // MARK: Reading

    /// Visits whose title or address contains `query` (case-insensitively), newest first. An
    /// empty query matches everything. `host` narrows them to the visits to exactly that host,
    /// case aside (`site:`, #118) — not to a longer host it is the start or end of.
    public func search(_ query: String, host: String? = nil) -> [HistoryVisit] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let matches = "(title LIKE ?1 ESCAPE '\\' OR url LIKE ?1 ESCAPE '\\')"
        guard let host else { return visits(where: matches, .text("%\(escaped)%")) }
        return visits(where: "host = ?2 AND \(matches)", .text("%\(escaped)%"), .text(host.lowercased()))
    }

    /// The PNG behind a visit's `faviconID`, `nil` once no visit shows it.
    public func favicon(_ id: String) -> Data? {
        var png: Data?
        db.query("SELECT png FROM favicons WHERE hash = ?1", .text(id)) { png = $0.blob(0) }
        return png
    }

    /// Visits at or after `date`, newest first.
    public func visits(since date: Date) -> [HistoryVisit] {
        visits(where: "visited_at >= ?1", .real(date.timeIntervalSinceReferenceDate))
    }

    /// Every calendar day that has visits, newest first, with how many (#116). Reads the visit times
    /// alone (the index has them), and works the calendar out once per day rather than per visit.
    public func dayCounts() -> [HistoryDayCount] {
        var counts: [HistoryDayCount] = []
        var current: (start: Date, end: Date, visits: Int)?
        db.query("SELECT visited_at FROM visits ORDER BY visited_at DESC") { row in
            let time = Date(timeIntervalSinceReferenceDate: row.double(0))
            if let day = current, time >= day.start, time < day.end {
                current?.visits += 1
                return
            }
            if let day = current { counts.append(HistoryDayCount(day: day.start, visits: day.visits)) }
            let (start, end) = bounds(ofDayContaining: time)
            current = (start, end, 1)
        }
        if let day = current { counts.append(HistoryDayCount(day: day.start, visits: day.visits)) }
        return counts
    }

    /// Visits on the calendar day containing `day`, newest first.
    public func visits(onDayOf day: Date) -> [HistoryVisit] {
        let (start, end) = bounds(ofDayContaining: day)
        return visits(
            where: "visited_at >= ?1 AND visited_at < ?2",
            .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate))
    }

    // MARK: Removing

    public func deleteVisits(_ ids: some Collection<HistoryVisit.ID>) {
        for id in ids {
            db.execute("DELETE FROM visits WHERE id = ?1", .integer(id))
        }
        removeUnshownFavicons()
    }

    /// Removes every visit on the calendar day containing `day`.
    public func deleteDay(containing day: Date) {
        let (start, end) = bounds(ofDayContaining: day)
        db.execute(
            "DELETE FROM visits WHERE visited_at >= ?1 AND visited_at < ?2",
            .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate))
        removeUnshownFavicons()
    }

    /// The retention limit: removes every visit before `date`.
    public func removeVisits(before date: Date) {
        db.execute("DELETE FROM visits WHERE visited_at < ?1", .real(date.timeIntervalSinceReferenceDate))
        removeUnshownFavicons()
    }

    /// 清除浏览数据: removes every visit at or after `date`.
    public func removeVisits(since date: Date) {
        db.execute("DELETE FROM visits WHERE visited_at >= ?1", .real(date.timeIntervalSinceReferenceDate))
        removeUnshownFavicons()
    }

    // MARK: - Favicons

    /// Keeps one copy of `png`, returning its key — `nil` when the database refused it.
    private func storeFavicon(_ png: Data) -> String? {
        let hash = Self.faviconHash(of: png)
        guard db.execute("INSERT OR IGNORE INTO favicons (hash, png) VALUES (?1, ?2)", .text(hash), .blob(png))
        else { return nil }
        return hash
    }

    /// A site icon's key: the SHA-256 of its bytes, so the same icon is one key wherever it is kept.
    static func faviconHash(of png: Data) -> String {
        SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
    }

    /// Icons go with the last visit that showed them: what the history no longer has, it doesn't
    /// keep a trace of either.
    private func removeUnshownFavicons() {
        db.execute(
            """
            DELETE FROM favicons WHERE NOT EXISTS (SELECT 1 FROM visits WHERE visits.favicon_hash = favicons.hash)
            """)
    }

    // MARK: - Rows

    /// What one row is keyed by: the whole address, minus the fragment.
    static func address(of url: URL) -> String {
        guard url.fragment != nil, var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url.absoluteString }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private func bounds(ofDayContaining day: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    private func visits(where condition: String, _ values: SQLiteDatabase.Value...) -> [HistoryVisit] {
        let sql = """
            SELECT id, url, title, visited_at, favicon_hash FROM visits
            WHERE \(condition) ORDER BY visited_at DESC, id DESC
            """
        var result: [HistoryVisit] = []
        db.query(sql, values) { row in
            guard let urlText = row.text(1), let url = URL(string: urlText) else { return }
            result.append(
                HistoryVisit(
                    id: row.int64(0), url: url, title: row.text(2),
                    visitedAt: Date(timeIntervalSinceReferenceDate: row.double(3)), faviconID: row.text(4)))
        }
        return result
    }
}
