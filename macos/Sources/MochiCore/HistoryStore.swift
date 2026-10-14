import CryptoKit
import Foundation
import SQLite3

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
/// A database that can't be used never blocks launch. Only a *damaged* one — SQLite reports it
/// corrupt or not a database, or `quick_check` finds a fault — is moved aside to `<name>.corrupt`
/// and an empty history started in its place. Anything else (the file locked by another
/// connection past the busy timeout, a permission problem, …) says nothing about the history
/// itself, so the file is left exactly as it is and this session keeps its history in memory:
/// what is visited now is lost at quit, but nothing already recorded is. Memory is also the last
/// resort when even a fresh file can't be made.
///
/// There is no migration: a file from when history kept one row per address keeps that old table,
/// unread, beside the timeline.
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

    /// Records one visit to `url` at the injected "now", made under `favicon` (a PNG) when one is
    /// already known, returning it for its title and icon to be written to — `nil` only when the
    /// database refused the row.
    @discardableResult
    public func recordVisit(to url: URL, favicon: Data? = nil) -> HistoryVisit.ID? {
        let faviconID = favicon.flatMap(storeFavicon)
        guard
            execute(
                "INSERT INTO visits (url, host, title, visited_at, favicon_hash) VALUES (?1, ?2, NULL, ?3, ?4)",
                .text(Self.address(of: url)), url.host.map { .text($0.lowercased()) } ?? .null,
                .real(now().timeIntervalSinceReferenceDate), faviconID.map(Value.text) ?? .null)
        else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    /// Sets the site icon of one visit (a PNG) — for an icon that arrives after the visit was
    /// recorded. Does nothing for a visit that isn't (or is no longer) recorded.
    public func updateFavicon(_ png: Data, ofVisit id: HistoryVisit.ID) {
        guard let faviconID = storeFavicon(png) else { return }
        execute("UPDATE visits SET favicon_hash = ?1 WHERE id = ?2", .text(faviconID), .integer(id))
        removeUnshownFavicons()
    }

    /// Sets the title of one visit — the last title a page reports while it is up is the one kept.
    /// Does nothing for a visit that isn't (or is no longer) recorded.
    public func updateTitle(_ title: String, ofVisit id: HistoryVisit.ID) {
        execute("UPDATE visits SET title = ?1 WHERE id = ?2", .text(title), .integer(id))
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
        guard let statement = prepare("SELECT png FROM favicons WHERE hash = ?1", [.text(id)]) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    /// Visits at or after `date`, newest first.
    public func visits(since date: Date) -> [HistoryVisit] {
        visits(where: "visited_at >= ?1", .real(date.timeIntervalSinceReferenceDate))
    }

    /// Every calendar day that has visits, newest first, with how many (#116). Reads the visit times
    /// alone (the index has them), and works the calendar out once per day rather than per visit.
    public func dayCounts() -> [HistoryDayCount] {
        guard let statement = prepare("SELECT visited_at FROM visits ORDER BY visited_at DESC", []) else { return [] }
        defer { sqlite3_finalize(statement) }
        var counts: [HistoryDayCount] = []
        var current: (start: Date, end: Date, visits: Int)?
        while sqlite3_step(statement) == SQLITE_ROW {
            let time = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 0))
            if let day = current, time >= day.start, time < day.end {
                current?.visits += 1
                continue
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
            execute("DELETE FROM visits WHERE id = ?1", .integer(id))
        }
        removeUnshownFavicons()
    }

    /// Removes every visit on the calendar day containing `day`.
    public func deleteDay(containing day: Date) {
        let (start, end) = bounds(ofDayContaining: day)
        execute(
            "DELETE FROM visits WHERE visited_at >= ?1 AND visited_at < ?2",
            .real(start.timeIntervalSinceReferenceDate), .real(end.timeIntervalSinceReferenceDate))
        removeUnshownFavicons()
    }

    /// The retention limit: removes every visit before `date`.
    public func removeVisits(before date: Date) {
        execute("DELETE FROM visits WHERE visited_at < ?1", .real(date.timeIntervalSinceReferenceDate))
        removeUnshownFavicons()
    }

    /// 清除浏览数据: removes every visit at or after `date`.
    public func removeVisits(since date: Date) {
        execute("DELETE FROM visits WHERE visited_at >= ?1", .real(date.timeIntervalSinceReferenceDate))
        removeUnshownFavicons()
    }

    // MARK: - Favicons

    /// Keeps one copy of `png`, returning its key — `nil` when the database refused it.
    private func storeFavicon(_ png: Data) -> String? {
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        guard execute("INSERT OR IGNORE INTO favicons (hash, png) VALUES (?1, ?2)", .text(hash), .blob(png))
        else { return nil }
        return hash
    }

    /// Icons go with the last visit that showed them: what the history no longer has, it doesn't
    /// keep a trace of either.
    private func removeUnshownFavicons() {
        execute(
            """
            DELETE FROM favicons WHERE NOT EXISTS (SELECT 1 FROM visits WHERE visits.favicon_hash = favicons.hash)
            """)
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
        case integer(Int64)
        case blob(Data)
        case null
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
            case .integer(let integer): sqlite3_bind_int64(statement, position, integer)
            case .blob(let data):
                _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), Self.transient) }
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    /// `false` when the statement couldn't be prepared or didn't run to completion.
    @discardableResult
    private func execute(_ sql: String, _ values: Value...) -> Bool {
        guard let statement = prepare(sql, values) else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func visits(where condition: String, _ values: Value...) -> [HistoryVisit] {
        let sql = """
            SELECT id, url, title, visited_at, favicon_hash FROM visits
            WHERE \(condition) ORDER BY visited_at DESC, id DESC
            """
        guard let statement = prepare(sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [HistoryVisit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(statement, 1), let url = URL(string: String(cString: urlText))
            else { continue }
            result.append(
                HistoryVisit(
                    id: sqlite3_column_int64(statement, 0), url: url,
                    title: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                    visitedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3)),
                    faviconID: sqlite3_column_text(statement, 4).map { String(cString: $0) }))
        }
        return result
    }
}
