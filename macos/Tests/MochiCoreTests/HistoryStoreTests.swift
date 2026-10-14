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

    @Test func aFirstVisitIsRecordedWithNoTitleYet() {
        let store = makeStore()

        let id = store.recordVisit(to: url("https://example.com/a"))

        #expect(
            store.visits(since: .distantPast) == [
                HistoryVisit(id: id!, url: url("https://example.com/a"), title: nil, visitedAt: clock.now)
            ])
    }

    /// History is a timeline: visiting the same address again is another visit, not a merge.
    @Test func everyVisitIsItsOwnRowEvenToTheSameAddress() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"))
        clock.now = clock.now.addingTimeInterval(60)
        store.recordVisit(to: url("https://example.com/b"))
        clock.now = clock.now.addingTimeInterval(60)
        store.recordVisit(to: url("https://example.com/a"))

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/a", "/b", "/a"])
    }

    /// Two visits in the same instant still come back in the order they happened.
    @Test func visitsInTheSameInstantKeepTheirOrder() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/first"))
        store.recordVisit(to: url("https://example.com/second"))

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/second", "/first"])
    }

    @Test func theFragmentIsNotPartOfTheAddress() {
        let store = makeStore()

        store.recordVisit(to: url("https://example.com/a#intro"))

        #expect(store.visits(since: .distantPast).map(\.url) == [url("https://example.com/a")])
    }

    /// The title belongs to the visit it was reported for: a later visit retitled doesn't rewrite
    /// what the page was called before.
    @Test func aTitleLandsOnlyOnTheVisitItIsGivenFor() {
        let store = makeStore()
        let first = store.recordVisit(to: url("https://example.com/a"))!
        store.updateTitle("Before", ofVisit: first)
        clock.now = clock.now.addingTimeInterval(60)
        let second = store.recordVisit(to: url("https://example.com/a"))!

        store.updateTitle("After", ofVisit: second)

        #expect(store.visits(since: .distantPast).map(\.title) == ["After", "Before"])
    }

    @Test func theLastTitleReceivedForAVisitWins() {
        let store = makeStore()
        let id = store.recordVisit(to: url("https://example.com/a"))!

        store.updateTitle("First", ofVisit: id)
        store.updateTitle("Second", ofVisit: id)

        #expect(store.visits(since: .distantPast).map(\.title) == ["Second"])
    }

    /// A title is only ever attached to a visit already recorded — never conjures one up.
    @Test func titlingAnUnknownVisitRecordsNothing() {
        let store = makeStore()

        store.updateTitle("Nowhere", ofVisit: 42)

        #expect(store.visits(since: .distantPast).isEmpty)
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
        store.updateTitle("The Swift Guide", ofVisit: store.recordVisit(to: url("https://example.com/swift"))!)
        clock.now = clock.now.addingTimeInterval(60)
        store.updateTitle("The Book — guide", ofVisit: store.recordVisit(to: url("https://doc.rust-lang.org/book"))!)

        #expect(store.search(row.query).map(\.url.absoluteString) == row.expected)
    }

    /// Each visit is matched on its own title, so a page renamed since still turns up under the name
    /// it had then.
    @Test func searchMatchesEachVisitByTheTitleItHad() {
        let store = makeStore()
        store.updateTitle("Old name", ofVisit: store.recordVisit(to: url("https://example.com/a"))!)
        clock.now = clock.now.addingTimeInterval(60)
        store.updateTitle("New name", ofVisit: store.recordVisit(to: url("https://example.com/a"))!)

        #expect(store.search("old").map(\.title) == ["Old name"])
        #expect(store.search("example").count == 2)
    }

    /// `site:` (#118): the host exactly — not a longer one it is the start of, not a subdomain —
    /// whatever its case, and the keywords on top.
    @Test(arguments: [
        (host: "knitpeople.com", text: "", expected: ["https://KnitPeople.com/b", "https://knitpeople.com/a"]),
        (host: "www.knitpeople.com", text: "", expected: ["https://www.knitpeople.com/"]),
        (host: "knitpeople.com.cn", text: "", expected: ["https://knitpeople.com.cn/"]),
        (host: "knitpeople.com", text: "Payroll", expected: ["https://knitpeople.com/a"]),
        (host: "example.com", text: "", expected: []),
    ])
    func searchCanBeNarrowedToOneHost(_ row: (host: String, text: String, expected: [String])) {
        let store = makeStore()
        for (address, title) in [
            ("https://knitpeople.com/a", "Payroll"), ("https://www.knitpeople.com/", "Payroll"),
            ("https://knitpeople.com.cn/", "Payroll"), ("https://KnitPeople.com/b", "Other"),
        ] {
            clock.now = clock.now.addingTimeInterval(60)
            store.updateTitle(title, ofVisit: store.recordVisit(to: url(address))!)
        }

        #expect(store.search(row.text, host: row.host).map(\.url.absoluteString) == row.expected)
    }

    // MARK: Days

    @Test func visitsAreGroupedByTheCalendarDayTheyHappenedOn() {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-11 23:59")
        store.recordVisit(to: url("https://example.com/late"))
        clock.now = historyTestDate("2026-10-12 00:00")
        store.recordVisit(to: url("https://example.com/midnight"))
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: url("https://example.com/morning"))

        #expect(
            store.visits(onDayOf: historyTestDate("2026-10-12 12:00")).map(\.url.path) == ["/morning", "/midnight"])
        #expect(store.visits(onDayOf: historyTestDate("2026-10-11 01:00")).map(\.url.path) == ["/late"])
    }

    /// #116: what a folded day needs — which days have visits, and how many — without reading a
    /// single visit.
    @Test func eachDayWithVisitsIsCountedNewestFirst() {
        let store = makeStore()
        for time in ["2026-10-01 08:00", "2026-10-11 23:59", "2026-10-12 00:00", "2026-10-12 09:00", "2026-10-12 09:01"] {
            clock.now = historyTestDate(time)
            store.recordVisit(to: url("https://example.com/a"))
        }

        #expect(
            store.dayCounts() == [
                HistoryDayCount(day: historyTestDate("2026-10-12 00:00"), visits: 3),
                HistoryDayCount(day: historyTestDate("2026-10-11 00:00"), visits: 1),
                HistoryDayCount(day: historyTestDate("2026-10-01 00:00"), visits: 1),
            ])
    }

    @Test func anEmptyHistoryHasNoDays() {
        #expect(makeStore().dayCounts().isEmpty)
    }

    /// A page visited on several days is on each of them.
    @Test func aPageVisitedOnTwoDaysIsOnBoth() {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-10 09:00")
        store.recordVisit(to: url("https://example.com/a"))
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: url("https://example.com/a"))

        #expect(store.visits(onDayOf: historyTestDate("2026-10-10 12:00")).map(\.url.path) == ["/a"])
        #expect(store.visits(onDayOf: historyTestDate("2026-10-12 12:00")).map(\.url.path) == ["/a"])
    }

    // MARK: Removing

    /// Deleting a visit leaves the other visits to the same page alone.
    @Test func deletingVisitsRemovesExactlyThoseVisits() {
        let store = makeStore()
        let a1 = store.recordVisit(to: url("https://example.com/a"))!
        store.recordVisit(to: url("https://example.com/b"))
        store.recordVisit(to: url("https://example.com/a"))
        let c = store.recordVisit(to: url("https://example.com/c"))!

        store.deleteVisits([a1, c])

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/a", "/b"])
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

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/after", "/before"])
    }

    /// The retention limit: every visit before the cut-off goes, even to a page visited since.
    @Test func removingVisitsBeforeAMomentKeepsThatMomentAndLater() {
        let store = makeStore()
        clock.now = historyTestDate("2025-10-12 09:59")
        store.recordVisit(to: url("https://example.com/old"))
        store.recordVisit(to: url("https://example.com/again"))
        clock.now = historyTestDate("2025-10-12 10:00")
        store.recordVisit(to: url("https://example.com/edge"))
        clock.now = historyTestDate("2026-10-12 10:00")
        store.recordVisit(to: url("https://example.com/again"))

        store.removeVisits(before: historyTestDate("2025-10-12 10:00"))

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/again", "/edge"])
    }

    /// 清除浏览数据's time range: every visit from the start onwards goes.
    @Test func removingVisitsSinceAMomentKeepsWhatCameBefore() {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-12 08:59")
        store.recordVisit(to: url("https://example.com/kept"))
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: url("https://example.com/edge"))
        clock.now = historyTestDate("2026-10-12 10:00")
        store.recordVisit(to: url("https://example.com/kept"))

        store.removeVisits(since: historyTestDate("2026-10-12 09:00"))

        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/kept"])
        #expect(store.visits(since: .distantPast).map(\.visitedAt) == [historyTestDate("2026-10-12 08:59")])
    }

    // MARK: Favicons (#117)

    private let iconA = Data("icon A".utf8)
    private let iconB = Data("icon B".utf8)

    @Test func aVisitKeepsTheIconItWasRecordedWith() throws {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"), favicon: iconA)
        store.recordVisit(to: url("https://example.com/b"))

        let visits = store.visits(since: .distantPast)

        #expect(visits.map { $0.faviconID == nil } == [true, false])
        #expect(store.favicon(try #require(visits[1].faviconID)) == iconA)
    }

    /// An icon that arrives after the visit is written to that visit alone — a site changing its
    /// icon later doesn't redraw the visits made under the old one.
    @Test func anIconLandsOnlyOnTheVisitItIsGivenFor() throws {
        let store = makeStore()
        let first = try #require(store.recordVisit(to: url("https://example.com/a")))
        store.updateFavicon(iconA, ofVisit: first)
        let second = try #require(store.recordVisit(to: url("https://example.com/a")))

        store.updateFavicon(iconB, ofVisit: second)

        let icons = store.visits(since: .distantPast).map { $0.faviconID.flatMap(store.favicon) }
        #expect(icons == [iconB, iconA])
    }

    /// The same bytes are one icon, however many visits show it.
    @Test func visitsWithTheSameIconShareIt() {
        let store = makeStore()
        store.recordVisit(to: url("https://example.com/a"), favicon: iconA)
        store.recordVisit(to: url("https://example.com/b"), favicon: Data("icon A".utf8))
        store.recordVisit(to: url("https://example.com/c"), favicon: iconB)

        let ids = store.visits(since: .distantPast).map(\.faviconID)

        #expect(ids[1] == ids[2])
        #expect(ids[0] != ids[1])
    }

    @Test func anIconForAnUnknownVisitRecordsNothing() {
        let store = makeStore()

        store.updateFavicon(iconA, ofVisit: 42)

        #expect(store.visits(since: .distantPast).isEmpty)
    }

    /// An icon no visit shows any more is gone with the last visit that showed it — whichever way
    /// that visit went — so the icons never outlive the history they came with.
    @Test(arguments: ["delete", "deleteDay", "retention", "clear", "replaced"])
    func anIconGoesWithTheLastVisitShowingIt(_ removal: String) throws {
        let store = makeStore()
        clock.now = historyTestDate("2026-10-11 09:00")
        let old = try #require(store.recordVisit(to: url("https://gone.example.com/"), favicon: iconA))
        clock.now = historyTestDate("2026-10-12 09:00")
        store.recordVisit(to: url("https://kept.example.com/"), favicon: iconB)
        let goneIcon = try #require(store.visits(onDayOf: historyTestDate("2026-10-11 12:00")).first?.faviconID)
        let keptIcon = try #require(store.visits(onDayOf: historyTestDate("2026-10-12 12:00")).first?.faviconID)

        switch removal {
        case "delete": store.deleteVisits([old])
        case "deleteDay": store.deleteDay(containing: historyTestDate("2026-10-11 12:00"))
        case "retention": store.removeVisits(before: historyTestDate("2026-10-12 00:00"))
        case "clear":
            // 清除浏览数据 from the start of the 11th takes both visits — and both icons.
            store.removeVisits(since: historyTestDate("2026-10-11 00:00"))
            #expect(store.favicon(keptIcon) == nil)
        default: store.updateFavicon(iconB, ofVisit: old)
        }

        #expect(store.favicon(goneIcon) == nil)
        if removal != "clear" { #expect(store.favicon(keptIcon) == iconB) }
    }

    /// Still shown by another visit, an icon stays when one of its visits goes.
    @Test func anIconStillShownStays() throws {
        let store = makeStore()
        let first = try #require(store.recordVisit(to: url("https://example.com/a"), favicon: iconA))
        store.recordVisit(to: url("https://example.com/b"), favicon: iconA)
        let icon = try #require(store.visits(since: .distantPast).first?.faviconID)

        store.deleteVisits([first])

        #expect(store.favicon(icon) == iconA)
    }

    // MARK: On disk

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func visitsSurviveReopeningTheFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("History.db")
        let clock = clock

        do {
            let store = HistoryStore(databaseURL: file, now: { clock.now }, calendar: historyTestCalendar)
            store.updateTitle("A", ofVisit: store.recordVisit(to: url("https://example.com/a"), favicon: iconA)!)
        }
        let reopened = HistoryStore(databaseURL: file, now: { clock.now }, calendar: historyTestCalendar)

        #expect(reopened.visits(since: .distantPast).map(\.title) == ["A"])
        #expect(reopened.visits(since: .distantPast).first?.faviconID.flatMap(reopened.favicon) == iconA)
    }

    /// No migration (#114): a file from when history kept one row per address still opens, its old
    /// rows are neither read nor removed, and the timeline starts empty beside them.
    @Test func aFileFromBeforeTheTimelineOpensWithAnEmptyTimeline() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("History.db")
        var old: OpaquePointer?
        #expect(sqlite3_open_v2(file.path, &old, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
        let oldSchema = """
            CREATE TABLE history (url TEXT PRIMARY KEY NOT NULL, title TEXT, last_visited REAL NOT NULL,
                visit_count INTEGER NOT NULL);
            INSERT INTO history VALUES ('https://example.com/old', 'Old', 0, 3);
            """
        #expect(sqlite3_exec(old, oldSchema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(old)

        let store = HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)

        #expect(store.visits(since: .distantPast).isEmpty)
        store.recordVisit(to: url("https://example.com/new"))
        #expect(store.visits(since: .distantPast).map(\.url.path) == ["/new"])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("History.db.corrupt").path))
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
        #expect(store.visits(since: .distantPast).count == 1)
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

        #expect(store.visits(since: .distantPast).isEmpty)
        store.recordVisit(to: url("https://example.com/a"))
        #expect(store.visits(since: .distantPast).count == 1)
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

        #expect(store.visits(since: .distantPast).map(\.url) == [url("https://example.com/this-session")])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("History.db.corrupt").path))
        #expect(try Data(contentsOf: file) == before)

        sqlite3_exec(other, "ROLLBACK", nil, nil, nil)
        sqlite3_close(other)
        let nextLaunch = HistoryStore(databaseURL: file, now: { Date() }, calendar: historyTestCalendar)
        #expect(nextLaunch.visits(since: .distantPast).map(\.url) == [url("https://example.com/kept")])
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

        #expect(store.visits(since: .distantPast).map(\.url) == [url("https://example.com/kept")])
    }
}
