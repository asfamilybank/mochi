import Foundation
import SQLite3

/// One SQLite file opened through the system's own `libsqlite3` — what `HistoryStore` (#102) and
/// `BookmarkStore` (#121) both stand on, so the rules for a file that can't be used are written
/// once.
///
/// A database that can't be used never blocks launch. Only a *damaged* one — SQLite reports it
/// corrupt or not a database, or `quick_check` finds a fault — is moved aside to `<name>.corrupt`
/// and an empty one started in its place. Anything else (the file locked by another connection
/// past the busy timeout, a permission problem, …) says nothing about the contents, so the file is
/// left exactly as it is and this session keeps its data in memory: what changes now is lost at
/// quit, but nothing already stored is. Memory is also the last resort when even a fresh file
/// can't be made.
///
/// Main thread only, like the stores that own it.
final class SQLiteDatabase {
    enum Value {
        case text(String)
        case real(Double)
        case integer(Int64)
        case blob(Data)
        case null
    }

    private var db: OpaquePointer?

    /// - Parameters:
    ///   - databaseURL: the database file, created along with its folder when missing; `nil`
    ///     keeps everything in memory (tests).
    ///   - schema: run on every open; must be idempotent (`IF NOT EXISTS`).
    ///   - busyTimeout: how long to wait for another connection's lock before giving up on the
    ///     file for this session.
    init(databaseURL: URL?, schema: String, busyTimeout: TimeInterval) {
        guard let databaseURL else {
            db = Self.openInMemory(schema: schema)
            return
        }
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch Self.open(path: databaseURL.path, schema: schema, busyTimeout: busyTimeout) {
        case .opened(let opened):
            db = opened
        case .unavailable:
            db = Self.openInMemory(schema: schema)
        case .damaged:
            Self.moveAside(databaseURL)
            if case .opened(let opened) = Self.open(path: databaseURL.path, schema: schema, busyTimeout: busyTimeout) {
                db = opened
            } else {
                db = Self.openInMemory(schema: schema)
            }
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// The rowid of the last row this connection inserted.
    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }

    /// `false` when the statement couldn't be prepared or didn't run to completion.
    @discardableResult
    func execute(_ sql: String, _ values: Value...) -> Bool {
        execute(sql, values)
    }

    @discardableResult
    func execute(_ sql: String, _ values: [Value]) -> Bool {
        guard let statement = prepare(sql, values) else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    /// Runs `sql` and hands each result row to `row`, in order; nothing when it can't be prepared.
    func query(_ sql: String, _ values: Value..., row: (Row) -> Void) {
        query(sql, values, row: row)
    }

    func query(_ sql: String, _ values: [Value], row: (Row) -> Void) {
        guard let statement = prepare(sql, values) else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            row(Row(statement: statement))
        }
    }

    /// Runs the statements in `body` as one transaction — all of them, or (when `body` returns
    /// `false`) none.
    func transaction(_ body: () -> Bool) {
        execute("BEGIN")
        execute(body() ? "COMMIT" : "ROLLBACK")
    }

    /// One result row, read by column index.
    struct Row {
        fileprivate let statement: OpaquePointer

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func double(_ column: Int32) -> Double {
            sqlite3_column_double(statement, column)
        }

        func int64(_ column: Int32) -> Int64 {
            sqlite3_column_int64(statement, column)
        }

        func blob(_ column: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }

    // MARK: - Opening

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

    private static func openInMemory(schema: String) -> OpaquePointer? {
        if case .opened(let db) = open(path: ":memory:", schema: schema, busyTimeout: 0) { db } else { nil }
    }

    /// Opens (creating if needed) and prepares the schema, waiting up to `busyTimeout` for a lock.
    /// `quick_check` catches a file whose header is fine but whose pages aren't.
    private static func open(path: String, schema: String, busyTimeout: TimeInterval) -> OpenResult {
        var db: OpaquePointer?
        let openCode = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard openCode == SQLITE_OK, let db else {
            sqlite3_close(db)
            return result(for: openCode)
        }
        sqlite3_busy_timeout(db, Int32(busyTimeout * 1000))
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
}
