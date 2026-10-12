import Foundation
import SQLite3
import Testing

@testable import MochiCore

/// A clock the tests move by hand.
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// Shanghai has no DST, so "a day" below is always 24 hours and the midnight arithmetic in the
/// tests is plain addition.
let historyTestCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}()

/// `yyyy-MM-dd HH:mm` in `historyTestCalendar`'s time zone.
func historyTestDate(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = historyTestCalendar
    formatter.timeZone = historyTestCalendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

/// Runs against a real in-memory SQLite database — the store's worth is in its queries, so there
/// is no fake.
@Suite struct HistoryStoreTests {
    private let clock = TestClock(historyTestDate("2026-10-12 10:00"))

    private func makeStore() -> HistoryStore {
        let clock = clock
        return HistoryStore(databaseURL: nil, now: { clock.now }, calendar: historyTestCalendar)
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: Recording

    @Test func aFirstVisitIsRecordedOnceWithNoTitleYet() {
        let store = makeStore()

        store.recordVisit(to: url("https://example.com/a"))

        #expect(
            store.entries(since: .distantPast) == [
                HistoryEntry(url: url("https://example.com/a"), title: nil, lastVisited: clock.now, visitCount: 1)
            ])
    }

    @Test func visitingTheSameAddressAgainMergesIntoOneEntry() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"))
        clock.now = clock.now.addingTimeInterval(60)

        store.recordVisit(to: url("https://example.com/a"))

        let entries = store.entries(since: .distantPast)
        #expect(entries.count == 1)
        #expect(entries.first?.visitCount == 2)
        #expect(entries.first?.lastVisited == clock.now)
    }

    @Test func theFragmentIsNotPartOfTheAddress() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a#intro"))
        store.recordVisit(to: url("https://example.com/a#usage"))

        let entries = store.entries(since: .distantPast)
        #expect(entries.map(\.url) == [url("https://example.com/a")])
        #expect(entries.first?.visitCount == 2)
    }

    /// The address is otherwise taken as a whole: a different query is a different page.
    @Test func aDifferentQueryIsADifferentEntry() {
        let store = makeStore()
        store.recordVisit(to: url("https://youtube.com/watch?v=1"))
        clock.now = clock.now.addingTimeInterval(1)
        store.recordVisit(to: url("https://youtube.com/watch?v=2"))

        #expect(
            store.entries(since: .distantPast).map(\.url) == [
                url("https://youtube.com/watch?v=2"), url("https://youtube.com/watch?v=1"),
            ])
    }

    @Test func theLastTitleReceivedWins() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"))

        store.updateTitle("First", for: url("https://example.com/a"))
        store.updateTitle("Second", for: url("https://example.com/a#section"))

        #expect(store.entries(since: .distantPast).first?.title == "Second")
    }

    /// A title is only ever attached to a visit already recorded — never conjures up an entry.
    @Test func updatingTheTitleOfAnUnvisitedAddressRecordsNothing() {
        let store = makeStore()

        store.updateTitle("Nowhere", for: url("https://example.com/never"))

        #expect(store.entries(since: .distantPast).isEmpty)
    }

    @Test func aRevisitKeepsTheTitle() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"))
        store.updateTitle("Kept", for: url("https://example.com/a"))

        store.recordVisit(to: url("https://example.com/a"))

        #expect(store.entries(since: .distantPast).first?.title == "Kept")
    }

    // MARK: Search

    @Test(arguments: [
        (query: "rust", expected: ["https://doc.rust-lang.org/book"]),  // the address
        (query: "Swift", expected: ["https://example.com/swift"]),  // the title
        (query: "SWIFT", expected: ["https://example.com/swift"]),  // case doesn't matter
        (query: "guide", expected: ["https://doc.rust-lang.org/book", "https://example.com/swift"]),
        (query: "50%", expected: []),  // `%` is a literal, not a wildcard
        (query: "", expected: ["https://doc.rust-lang.org/book", "https://example.com/swift"]),
    ])
    func searchMatchesTitleOrAddressNewestFirst(_ row: (query: String, expected: [String])) {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/swift"))
        store.updateTitle("The Swift Guide", for: url("https://example.com/swift"))
        clock.now = clock.now.addingTimeInterval(60)
        store.recordVisit(to: url("https://doc.rust-lang.org/book"))
        store.updateTitle("The Book — guide", for: url("https://doc.rust-lang.org/book"))

        #expect(store.search(row.query).map(\.url.absoluteString) == row.expected)
    }

    // MARK: Days

    @Test func entriesAreGroupedByTheCalendarDayOfTheirLastVisit() {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-11 23:59")
        store.recordVisit(to: url("https://example.com/late"))
        clock.now = historyTestDate("2026-10-12 00:00")
        store.recordVisit(to: url("https://example.com/midnight"))
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: url("https://example.com/morning"))

        #expect(
            store.entries(onDayOf: historyTestDate("2026-10-12 12:00")).map(\.url.path) == ["/morning", "/midnight"])
        #expect(store.entries(onDayOf: historyTestDate("2026-10-11 01:00")).map(\.url.path) == ["/late"])
    }

    @Test func onlyDaysThatHaveEntriesAreListedNewestFirst() {
        let store = makeStore()
        for day in ["2026-10-01 08:00", "2026-10-09 23:30", "2026-10-12 00:10", "2026-10-12 09:00"] {
            clock.now = historyTestDate(day)
            store.recordVisit(to: url("https://example.com/\(day.prefix(10))-\(day.suffix(5))"))
        }

        #expect(
            store.daysWithEntries(since: historyTestDate("2026-10-06 00:00")) == [
                historyTestDate("2026-10-12 00:00"), historyTestDate("2026-10-09 00:00"),
            ])
    }

    // MARK: Removing

    @Test func deletingEntriesRemovesExactlyThoseAddresses() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"))
        store.recordVisit(to: url("https://example.com/b"))
        store.recordVisit(to: url("https://example.com/c"))

        store.deleteEntries(for: [url("https://example.com/a"), url("https://example.com/c#x")])

        #expect(store.entries(since: .distantPast).map(\.url.path) == ["/b"])
    }

    @Test func deletingADayLeavesTheDaysAroundIt() {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-10 23:59")
        store.recordVisit(to: url("https://example.com/before"))
        clock.now = historyTestDate("2026-10-11 00:00")
        store.recordVisit(to: url("https://example.com/first"))
        clock.now = historyTestDate("2026-10-11 23:59")
        store.recordVisit(to: url("https://example.com/last"))
        clock.now = historyTestDate("2026-10-12 00:00")
        store.recordVisit(to: url("https://example.com/after"))

        store.deleteDay(containing: historyTestDate("2026-10-11 12:00"))

        #expect(store.entries(since: .distantPast).map(\.url.path) == ["/after", "/before"])
    }

    /// The retention limit: everything last visited before the cut-off goes.
    @Test func removingEntriesVisitedBeforeAMomentKeepsThatMomentAndLater() {
        let store = makeStore()
        clock.now = historyTestDate("2025-10-12 09:59")
        store.recordVisit(to: url("https://example.com/old"))
        clock.now = historyTestDate("2025-10-12 10:00")
        store.recordVisit(to: url("https://example.com/edge"))
        clock.now = historyTestDate("2026-10-12 10:00")
        store.recordVisit(to: url("https://example.com/new"))

        store.removeEntries(visitedBefore: historyTestDate("2025-10-12 10:00"))

        #expect(store.entries(since: .distantPast).map(\.url.path) == ["/new", "/edge"])
    }

    /// 清除浏览数据's time range: everything last visited from the start onwards goes.
    @Test func removingEntriesVisitedSinceAMomentKeepsWhatCameBefore() {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-12 08:59")
        store.recordVisit(to: url("https://example.com/kept"))
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: url("https://example.com/edge"))
        clock.now = historyTestDate("2026-10-12 10:00")
        store.recordVisit(to: url("https://example.com/new"))

        store.removeEntries(visitedSince: historyTestDate("2026-10-12 09:00"))

        #expect(store.entries(since: .distantPast).map(\.url.path) == ["/kept"])
    }

    // MARK: On disk

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func entriesSurviveReopeningTheFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("History.db")
        let clock = clock

        do {
            let store = HistoryStore(databaseURL: file, now: { clock.now }, calendar: historyTestCalendar)
            store.recordVisit(to: url("https://example.com/a"))
            store.updateTitle("A", for: url("https://example.com/a"))
        }
        let reopened = HistoryStore(databaseURL: file, now: { clock.now }, calendar: historyTestCalendar)

        #expect(reopened.entries(since: .distantPast).map(\.title) == ["A"])
    }

    /// Creates `Mochi/` under Application Support when it isn't there yet (a first launch, or the
    /// user deleted it).
    @Test func theFilesFolderIsCreatedWhenMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Mochi/History.db")

        let store = HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)
        store.recordVisit(to: url("https://example.com/a"))

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.entries(since: .distantPast).count == 1)
    }

    /// A damaged history must never stand in the way of launching: the file is moved aside (not
    /// deleted — it may still be recoverable by hand) and history starts over, empty.
    @Test func aCorruptFileIsMovedAsideAndHistoryStartsOverEmpty() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("History.db")
        let garbage = Data(repeating: 0x5A, count: 8192)
        try garbage.write(to: file)

        let store = HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)

        #expect(store.entries(since: .distantPast).isEmpty)
        store.recordVisit(to: url("https://example.com/a"))
        #expect(store.entries(since: .distantPast).count == 1)
        let movedAside = directory.appendingPathComponent("History.db.corrupt")
        #expect(try Data(contentsOf: movedAside) == garbage)
        #expect(try Data(contentsOf: file) != garbage)
    }

    /// Only damage moves the file aside. A healthy history another connection happens to hold
    /// locked — a second Mochi, a backup tool — is left exactly as it is: this session keeps its
    /// history in memory, and the next launch finds every entry still there.
    @Test func aLockedFileIsLeftAloneAndThisSessionKeepsHistoryInMemory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("History.db")
        do {
            HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)
                .recordVisit(to: url("https://example.com/kept"))
        }
        let before = try Data(contentsOf: file)
        var other: OpaquePointer?
        #expect(sqlite3_open_v2(file.path, &other, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        #expect(sqlite3_exec(other, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)

        let store = HistoryStore(
            databaseURL: file, now: { Date() }, calendar: historyTestCalendar, busyTimeout: 0.05)
        store.recordVisit(to: url("https://example.com/this-session"))

        #expect(store.entries(since: .distantPast).map(\.url) == [url("https://example.com/this-session")])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("History.db.corrupt").path))
        #expect(try Data(contentsOf: file) == before)

        sqlite3_exec(other, "ROLLBACK", nil, nil, nil)
        sqlite3_close(other)
        let nextLaunch = HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)
        #expect(nextLaunch.entries(since: .distantPast).map(\.url) == [url("https://example.com/kept")])
    }

    /// A lock held only briefly is waited out rather than given up on.
    @Test func aBrieflyHeldLockIsWaitedOut() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("History.db")
        do {
            HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)
                .recordVisit(to: url("https://example.com/kept"))
        }
        var other: OpaquePointer?
        #expect(sqlite3_open_v2(file.path, &other, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        #expect(sqlite3_exec(other, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        let lockHolder = other
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            sqlite3_exec(lockHolder, "ROLLBACK", nil, nil, nil)
            sqlite3_close(lockHolder)
        }

        let store = HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar, busyTimeout: 5)

        #expect(store.entries(since: .distantPast).map(\.url) == [url("https://example.com/kept")])
    }
}
