import Foundation
import SQLite3

/// One page in the history (`CONTEXT.md`「历史记录」): an address visited at least once, with the
/// last title it reported, when it was last visited and how many times in all.
public struct HistoryEntry: Equatable, Sendable {
    public let url: URL
    /// `nil` until the page reports one.
    public let title: String?
    public let lastVisited: Date
    public let visitCount: Int

    public init(url: URL, title: String?, lastVisited: Date, visitCount: Int) {
        self.url = url
        self.title = title
        self.lastVisited = lastVisited
        self.visitCount = visitCount
    }
}

/// Mochi's history, kept in SQLite (`Application Support/Mochi/History.db`) through the system's
/// own `libsqlite3` — no dependency added (#102). The interface is shaped by what the app does with
/// history; no SQL leaks out.
///
/// One row per address: the address is the whole URL minus its `#` fragment (a fragment only
/// points somewhere inside the same page), so revisiting merges into the existing row — the visit
/// count goes up and the last-visited time moves forward.
///
/// "Now" and the calendar that decides where one day ends and the next begins are injected, so
/// day grouping can be tested across midnight without waiting for one.
///
/// A database that can't be used never blocks launch. Only a *damaged* one — SQLite reports it
/// corrupt or not a database, or `quick_check` finds a fault — is moved aside to `<name>.corrupt`
/// and an empty history started in its place. Anything else (the file locked by another
/// connection past the busy timeout, a permission problem, …) says nothing about the history
/// itself, so the file is left exactly as it is and this session keeps its history in memory:
/// what is visited now is lost at quit, but nothing already recorded is. Memory is also the last
/// resort when even a fresh file can't be made.
///
/// Main thread only, like everything else that touches it.
public final class HistoryStore {
    public let now: () -> Date
    public let calendar: Calendar
    private var db: OpaquePointer?

    /// `Application Support/Mochi/History.db`, next to `config.toml`.
    public static var defaultDatabaseURL: URL {
        WidgetConfig.defaultConfigURL.deletingLastPathComponent().appendingPathComponent("History.db")
    }

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
        guard let databaseURL else {
            db = Self.openInMemory()
            return
        }
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch Self.open(path: databaseURL.path, busyTimeout: busyTimeout) {
        case .opened(let opened):
            db = opened
        case .unavailable:
            db = Self.openInMemory()
        case .damaged:
            Self.moveAside(databaseURL)
            if case .opened(let opened) = Self.open(path: databaseURL.path, busyTimeout: busyTimeout) {
                db = opened
            } else {
                db = Self.openInMemory()
            }
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Recording

    /// Records one visit to `url` at the injected "now".
    public func recordVisit(to url: URL) {
        execute(
            """
            INSERT INTO history (url, title, last_visited, visit_count) VALUES (?1, NULL, ?2, 1)
            ON CONFLICT(url) DO UPDATE SET last_visited = excluded.last_visited, visit_count = visit_count + 1
            """,
            .text(Self.address(of: url)), .real(now().timeIntervalSinceReferenceDate))
    }

    /// Sets the title of `url`'s entry — the last title a page reports is the one kept. Does
    /// nothing when `url` has never been recorded.
    public func updateTitle(_ title: String, for url: URL) {
        execute("UPDATE history SET title = ?1 WHERE url = ?2", .text(title), .text(Self.address(of: url)))
    }

    // MARK: Reading

    /// Entries whose title or address contains `query` (case-insensitively), newest first. An
    /// empty query matches everything.
    public func search(_ query: String) -> [HistoryEntry] {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return entries(
            where: "title LIKE ?1 ESCAPE '\\' OR url LIKE ?1 ESCAPE '\\'", .text("%\(escaped)%"))
    }

    /// Entries last visited at or after `date`, newest first.
    public func entries(since date: Date) -> [HistoryEntry] {
        entries(where: "last_visited >= ?1", .real(date.timeIntervalSinceReferenceDate))
    }

    /// Entries last visited on the calendar day containing `day`, newest first.
    public func entries(onDayOf day: Date) -> [HistoryEntry] {
        let (start, end) = bounds(ofDayContaining: day)
        return entries(
            where: "last_visited >= ?1 AND last_visited < ?2",
            .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate))
    }

    /// The start of every calendar day since `date` that has at least one entry, newest first.
    public func daysWithEntries(since date: Date) -> [Date] {
        var days: [Date] = []
        for entry in entries(since: date) {
            let day = calendar.startOfDay(for: entry.lastVisited)
            if days.last != day { days.append(day) }
        }
        return days
    }

    // MARK: Removing

    public func deleteEntries(for urls: [URL]) {
        for url in urls {
            execute("DELETE FROM history WHERE url = ?1", .text(Self.address(of: url)))
        }
    }

    /// Removes every entry last visited on the calendar day containing `day`.
    public func deleteDay(containing day: Date) {
        let (start, end) = bounds(ofDayContaining: day)
        execute(
            "DELETE FROM history WHERE last_visited >= ?1 AND last_visited < ?2",
            .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate))
    }

    /// The retention limit: removes everything last visited before `date`.
    public func removeEntries(visitedBefore date: Date) {
        execute("DELETE FROM history WHERE last_visited < ?1", .real(date.timeIntervalSinceReferenceDate))
    }

    /// 清除浏览数据: removes everything last visited at or after `date`.
    public func removeEntries(visitedSince date: Date) {
        execute("DELETE FROM history WHERE last_visited >= ?1", .real(date.timeIntervalSinceReferenceDate))
    }

    // MARK: - SQLite

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

    private enum Value {
        case text(String)
        case real(Double)
    }

    /// `SQLITE_TRANSIENT`, which the C macro defines as `-1` cast to a destructor — Swift can't
    /// import it: SQLite copies the bound bytes before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private enum OpenResult {
        case opened(OpaquePointer)
        /// The file itself is broken: worth moving aside.
        case damaged
        /// Couldn't be used this time — locked, unreadable, … — which says nothing about its
        /// contents.
        case unavailable
    }

    /// Only these result codes mean the file's contents are broken.
    private static func result(for code: Int32) -> OpenResult {
        switch code & 0xFF {
        case SQLITE_CORRUPT, SQLITE_NOTADB: .damaged
        default: .unavailable
        }
    }

    private static func openInMemory() -> OpaquePointer? {
        if case .opened(let db) = open(path: ":memory:", busyTimeout: 0) { db } else { nil }
    }

    /// Opens (creating if needed) and prepares the schema, waiting up to `busyTimeout` for a lock.
    /// `quick_check` catches a file whose header is fine but whose pages aren't.
    private static func open(path: String, busyTimeout: TimeInterval) -> OpenResult {
        var db: OpaquePointer?
        let openCode = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openCode == SQLITE_OK, let db else {
            sqlite3_close(db)
            return result(for: openCode)
        }
        sqlite3_busy_timeout(db, Int32(busyTimeout * 1000))
        let schema = """
            CREATE TABLE IF NOT EXISTS history (
                url TEXT PRIMARY KEY NOT NULL,
                title TEXT,
                last_visited REAL NOT NULL,
                visit_count INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS history_last_visited ON history (last_visited);
            PRAGMA user_version = 1;
            """
        let schemaCode = sqlite3_exec(db, schema, nil, nil, nil)
        guard schemaCode == SQLITE_OK else {
            sqlite3_close(db)
            return result(for: schemaCode)
        }
        if let failure = quickCheckFailure(db) {
            sqlite3_close(db)
            return failure
        }
        return .opened(db)
    }

    /// `nil` when `quick_check` reports `ok`; `.damaged` when it reports anything else or SQLite
    /// finds the file corrupt while checking; `.unavailable` when the check couldn't run.
    private static func quickCheckFailure(_ db: OpaquePointer) -> OpenResult? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let prepareCode = sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil)
        guard prepareCode == SQLITE_OK else { return result(for: prepareCode) }
        let stepCode = sqlite3_step(statement)
        guard stepCode == SQLITE_ROW else { return result(for: stepCode) }
        guard let text = sqlite3_column_text(statement, 0), String(cString: text) == "ok" else { return .damaged }
        return nil
    }

    /// Moves the damaged file (and any journal SQLite left beside it) to `<name>.corrupt`,
    /// replacing an older one.
    private static func moveAside(_ databaseURL: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: databaseURL.path + ".corrupt" + suffix)
            try? fileManager.removeItem(at: destination)
            if (try? fileManager.moveItem(at: source, to: destination)) == nil {
                try? fileManager.removeItem(at: source)
            }
        }
    }

    private func prepare(_ sql: String, _ values: [Value]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .real(let real): sqlite3_bind_double(statement, position, real)
            }
        }
        return statement
    }

    private func execute(_ sql: String, _ values: Value...) {
        guard let statement = prepare(sql, values) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
    }

    private func entries(where condition: String, _ values: Value...) -> [HistoryEntry] {
        let sql = """
            SELECT url, title, last_visited, visit_count FROM history
            WHERE \(condition) ORDER BY last_visited DESC, rowid DESC
            """
        guard let statement = prepare(sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [HistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: urlText))
            else { continue }
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            result.append(
                HistoryEntry(
                    url: url, title: title,
                    lastVisited: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
                    visitCount: Int(sqlite3_column_int64(statement, 3))))
        }
        return result
    }
}
