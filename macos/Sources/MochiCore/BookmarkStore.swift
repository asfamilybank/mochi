import Foundation

/// One bookmark (`CONTEXT.md`「书签」, ADR-0033): a page the user kept, under a name of their own.
public struct Bookmark: Equatable, Identifiable, Sendable {
    public typealias ID = Int64

    public let id: ID
    public let name: String
    /// The address minus its `#` fragment — one bookmark per address.
    public let url: URL
    /// A key for `BookmarkStore.favicon(_:)` — the SHA-256 of the icon's bytes, so it changes when
    /// the icon does; `nil` until the bookmark has one.
    public let faviconID: String?

    public init(id: ID, name: String, url: URL, faviconID: String?) {
        self.id = id
        self.name = name
        self.url = url
        self.faviconID = faviconID
    }
}

/// Why a bookmark couldn't be added or take an address.
public enum BookmarkRefusal: Error, Equatable, Sendable {
    /// Another bookmark already has the address — one bookmark per address.
    case alreadyBookmarked(Bookmark)
    /// The database refused the write.
    case notSaved
}

/// The bookmarks, kept in SQLite (`Application Support/Mochi/Bookmarks.db`) — a file of their own,
/// so a damaged history is never a reason to lose them, and no clearing of history or website data
/// reaches them (ADR-0033). Only the user deletes a bookmark.
///
/// One flat list in the user's order. Each bookmark keeps its own site icon: there are few of
/// them, so the bytes sit in the row rather than shared by hash the way history's are.
///
/// Main thread only, like everything else that touches it.
public final class BookmarkStore {
    private let db: SQLiteDatabase

    /// `Application Support/Mochi/Bookmarks.db`, beside `History.db`.
    public static var defaultDatabaseURL: URL {
        HistoryStore.defaultDatabaseURL.deletingLastPathComponent().appendingPathComponent("Bookmarks.db")
    }

    private static let schema = """
        CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL UNIQUE,
            position INTEGER NOT NULL,
            favicon BLOB,
            favicon_hash TEXT
        );
        PRAGMA user_version = 1;
        """

    /// - Parameter databaseURL: the database file, created along with its folder when missing;
    ///   `nil` keeps the bookmarks in memory (tests).
    public init(databaseURL: URL?, busyTimeout: TimeInterval = 2) {
        db = SQLiteDatabase(databaseURL: databaseURL, schema: Self.schema, busyTimeout: busyTimeout)
    }

    // MARK: Reading

    /// Every bookmark, in the user's order.
    public func all() -> [Bookmark] {
        bookmarks(where: "1")
    }

    /// The bookmark for `url`'s address (fragment aside), if there is one.
    public func bookmark(for url: URL) -> Bookmark? {
        bookmarks(where: "url = ?1", .text(HistoryStore.address(of: url))).first
    }

    /// The PNG behind a bookmark's `faviconID`, `nil` once no bookmark has it.
    public func favicon(_ id: String) -> Data? {
        var png: Data?
        db.query("SELECT favicon FROM bookmarks WHERE favicon_hash = ?1 LIMIT 1", .text(id)) { png = $0.blob(0) }
        return png
    }

    // MARK: Changing

    /// Adds a bookmark at the end of the list — or, when `url`'s address already is one, names
    /// that one and adds nothing.
    @discardableResult
    public func add(name: String, url: URL, favicon: Data? = nil) -> Result<Bookmark, BookmarkRefusal> {
        if let existing = bookmark(for: url) { return .failure(.alreadyBookmarked(existing)) }
        var nextPosition: Int64 = 0
        db.query("SELECT COALESCE(MAX(position) + 1, 0) FROM bookmarks") { nextPosition = $0.int64(0) }
        let address = HistoryStore.address(of: url)
        guard
            db.execute(
                "INSERT INTO bookmarks (name, url, position, favicon, favicon_hash) VALUES (?1, ?2, ?3, ?4, ?5)",
                .text(name), .text(address), .integer(nextPosition), favicon.map(SQLiteDatabase.Value.blob) ?? .null,
                favicon.map { .text(HistoryStore.faviconHash(of: $0)) } ?? .null)
        else { return .failure(.notSaved) }
        return .success(
            Bookmark(
                id: db.lastInsertRowID, name: name, url: URL(string: address) ?? url,
                faviconID: favicon.map(HistoryStore.faviconHash)))
    }

    public func rename(_ id: Bookmark.ID, to name: String) {
        db.execute("UPDATE bookmarks SET name = ?1 WHERE id = ?2", .text(name), .integer(id))
    }

    /// Points the bookmark at `url`'s address, keeping its name and place — `nil` when done, or
    /// the other bookmark that already has that address.
    @discardableResult
    public func changeURL(_ id: Bookmark.ID, to url: URL) -> BookmarkRefusal? {
        if let existing = bookmark(for: url), existing.id != id { return .alreadyBookmarked(existing) }
        db.execute("UPDATE bookmarks SET url = ?1 WHERE id = ?2", .text(HistoryStore.address(of: url)), .integer(id))
        return nil
    }

    /// Moves the bookmark to `index` in the list (clamped to the end), shifting the ones between.
    public func move(_ id: Bookmark.ID, to index: Int) {
        var order = all().map(\.id)
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: min(max(index, 0), order.count))
        db.transaction {
            order.enumerated().allSatisfy { position, id in
                db.execute("UPDATE bookmarks SET position = ?1 WHERE id = ?2", .integer(Int64(position)), .integer(id))
            }
        }
    }

    public func delete(_ ids: some Collection<Bookmark.ID>) {
        for id in ids {
            db.execute("DELETE FROM bookmarks WHERE id = ?1", .integer(id))
        }
    }

    /// Replaces the bookmark's site icon with `png`.
    public func updateFavicon(_ png: Data, of id: Bookmark.ID) {
        db.execute(
            "UPDATE bookmarks SET favicon = ?1, favicon_hash = ?2 WHERE id = ?3",
            .blob(png), .text(HistoryStore.faviconHash(of: png)), .integer(id))
    }

    // MARK: - Rows

    private func bookmarks(where condition: String, _ values: SQLiteDatabase.Value...) -> [Bookmark] {
        var result: [Bookmark] = []
        db.query("SELECT id, name, url, favicon_hash FROM bookmarks WHERE \(condition) ORDER BY position, id", values) {
            row in
            guard let name = row.text(1), let urlText = row.text(2), let url = URL(string: urlText) else { return }
            result.append(Bookmark(id: row.int64(0), name: name, url: url, faviconID: row.text(3)))
        }
        return result
    }
}
