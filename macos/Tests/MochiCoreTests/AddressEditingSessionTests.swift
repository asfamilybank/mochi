import Foundation
import Testing

@testable import MochiCore

/// 地址栏建议 (#122, ADR-0034): what the Smart Address Field shows and does while the user types —
/// the list under it, its first row saying what Return does, ↑↓, Return, and Esc in three steps.
@Suite struct AddressEditingSessionTests {
    private let now = historyTestDate("2026-10-12 10:00")

    private func candidate(
        _ url: String, title: String? = nil, frecency: Double = 100, visited: String = "2026-10-12 09:00"
    ) -> AddressSuggestionCandidate {
        AddressSuggestionCandidate(
            url: URL(string: url)!, title: title, faviconID: nil, lastVisitedAt: historyTestDate(visited),
            frecency: frecency)
    }

    private func session(
        original: String = "https://current.example.com/", _ candidates: [AddressSuggestionCandidate] = []
    ) -> AddressEditingSession {
        AddressEditingSession(originalText: original, searchEngine: .google) { _ in candidates }
    }

    /// The pages the list offers below its first row, by address.
    private func pages(_ session: AddressEditingSession) -> [String] {
        session.rows.compactMap {
            if case .page(let page) = $0 { page.url.absoluteString } else { nil }
        }
    }

    // MARK: Beginning

    @Test func itStartsWithThePagesAddressAndNoList() {
        let session = session()

        #expect(session.fieldText == "https://current.example.com/")
        #expect(!session.isListVisible)
        #expect(session.rows.isEmpty)
    }

    // MARK: The first row: what Return does

    @Test(arguments: [
        (typed: "github.com", row: AddressSuggestionRow.open(URL(string: "https://github.com")!)),
        (typed: "localhost:3000", row: .open(URL(string: "https://localhost:3000")!)),
        (typed: "swift testing", row: .search(query: "swift testing", engine: .google)),
        (typed: "git", row: .search(query: "git", engine: .google)),
    ])
    func theFirstRowSaysWhatReturnDoes(_ row: (typed: String, row: AddressSuggestionRow)) {
        let session = session()

        session.textChanged(to: row.typed, byDeleting: false)

        #expect(session.isListVisible)
        #expect(session.rows.first == row.row)
        #expect(session.selectedIndex == 0)
    }

    @Test func theSearchFollowsTheConfiguredEngine() {
        let session = AddressEditingSession(originalText: "", searchEngine: .baidu) { _ in [] }

        session.textChanged(to: "git", byDeleting: false)

        #expect(session.rows.first == .search(query: "git", engine: .baidu))
    }

    @Test func clearingTheTextHidesTheList() {
        let session = session([candidate("https://github.com/")])
        session.textChanged(to: "git", byDeleting: false)

        session.textChanged(to: "  ", byDeleting: true)

        #expect(!session.isListVisible)
        #expect(session.rows.isEmpty)
    }

    // MARK: Matching

    @Test(arguments: [
        (typed: "git", matches: true),
        (typed: "GIT", matches: true),
        (typed: "hub", matches: false),
        (typed: "mochi", matches: true),
        (typed: "asfam", matches: true),
        (typed: "github.com/asf", matches: true),
        (typed: "https://github.com/asf", matches: true),
        (typed: "com", matches: true),
        (typed: "www", matches: false),
        (typed: "https", matches: false),
        (typed: "仓库", matches: true),
        (typed: "库", matches: true),
        (typed: "mochi 仓库", matches: true),
        (typed: "mochi swift", matches: false),
    ])
    func eachWordTypedMustStartAWordOfTheAddressOrTitle(_ row: (typed: String, matches: Bool)) {
        let session = session([candidate("https://www.github.com/asfamilybank/mochi", title: "Mochi 的仓库")])

        session.textChanged(to: row.typed, byDeleting: false)

        #expect(pages(session) == (row.matches ? ["https://www.github.com/asfamilybank/mochi"] : []))
    }

    /// A word start inside latin text is where the run of letters and digits begins; CJK has no
    /// spaces, so a match may begin at any character there.
    @Test(arguments: [
        (title: "廖雪峰Git教程", typed: "教程", matches: true),
        (title: "廖雪峰Git教程", typed: "git", matches: true),
        (title: "TheGitBook", typed: "git", matches: false),
        (title: "the-git-book", typed: "git", matches: true),
    ])
    func wordStartsInMixedText(_ row: (title: String, typed: String, matches: Bool)) {
        let session = session([candidate("https://example.com/", title: row.title)])

        session.textChanged(to: row.typed, byDeleting: false)

        #expect(pages(session) == (row.matches ? ["https://example.com/"] : []))
    }

    // MARK: Ranking

    @Test func moreFrecentPagesComeFirst() {
        let session = session([
            candidate("https://github.com/a", frecency: 30),
            candidate("https://github.com/b", frecency: 300),
            candidate("https://github.com/c", frecency: 100),
        ])

        session.textChanged(to: "github", byDeleting: false)

        #expect(pages(session) == ["https://github.com/b", "https://github.com/c", "https://github.com/a"])
    }

    @Test func onEqualFrecencyTheLatestVisitComesFirst() {
        let session = session([
            candidate("https://github.com/a", visited: "2026-10-11 09:00"),
            candidate("https://github.com/b", visited: "2026-10-12 09:00"),
        ])

        session.textChanged(to: "github", byDeleting: false)

        #expect(pages(session) == ["https://github.com/b", "https://github.com/a"])
    }

    /// Eight rows at most, the first among them.
    @Test func theListHoldsEightRowsAtMost() {
        let session = session((0..<20).map { candidate("https://github.com/\($0)", frecency: Double(100 - $0)) })

        session.textChanged(to: "github", byDeleting: false)

        #expect(session.rows.count == 8)
        #expect(pages(session) == (0..<7).map { "https://github.com/\($0)" })
    }

    @Test func eachAddressIsListedOnce() {
        let session = session([candidate("https://github.com/"), candidate("https://github.com/")])

        session.textChanged(to: "github", byDeleting: false)

        #expect(pages(session) == ["https://github.com/"])
    }

    /// The words typed are what the candidates are asked for — the store's coarse filter.
    @Test func theCandidatesAreAskedForWithTheWordsTyped() {
        var asked: [[String]] = []
        let session = AddressEditingSession(originalText: "", searchEngine: .google) { words in
            asked.append(words)
            return []
        }

        session.textChanged(to: "  Mochi   https://www.Git ", byDeleting: false)

        #expect(asked == [["mochi", "git"]])
    }

    // MARK: ↑↓ and Return

    @Test func movingDownShowsTheSelectedPagesAddressAndReturnOpensIt() {
        let session = session([candidate("https://github.com/a", frecency: 200), candidate("https://github.com/b")])
        session.textChanged(to: "github", byDeleting: false)

        session.moveSelection(by: 1)
        #expect(session.selectedIndex == 1)
        #expect(session.fieldText == "https://github.com/a")
        session.moveSelection(by: 1)
        #expect(session.fieldText == "https://github.com/b")

        #expect(session.enter() == .navigate(URL(string: "https://github.com/b")!))
    }

    @Test func movingBackToTheFirstRowPutsTheTypedTextBack() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "github", byDeleting: false)
        session.moveSelection(by: 1)

        session.moveSelection(by: -1)

        #expect(session.selectedIndex == 0)
        #expect(session.fieldText == "github")
    }

    @Test func theSelectionStaysWithinTheList() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "github", byDeleting: false)

        session.moveSelection(by: -1)
        #expect(session.selectedIndex == 0)
        session.moveSelection(by: 5)
        #expect(session.selectedIndex == 1)
    }

    @Test(arguments: [
        (typed: "github.com", target: "https://github.com"),
        (typed: "git", target: "https://www.google.com/search?q=git"),
    ])
    func returnOnTheFirstRowDoesWhatItSays(_ row: (typed: String, target: String)) {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: row.typed, byDeleting: false)

        #expect(session.enter() == .navigate(URL(string: row.target)!))
    }

    @Test func returnWithNothingTypedDoesNothing() {
        let session = session(original: "")

        #expect(session.enter() == .none)
    }

    /// Return before anything is typed reloads the address as it stands.
    @Test func returnOnTheUntouchedAddressGoesThere() {
        let session = session()

        #expect(session.enter() == .navigate(URL(string: "https://current.example.com/")!))
    }

    @Test func clickingARowOpensIt() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "github", byDeleting: false)

        #expect(session.choose(row: 1) == .navigate(URL(string: "https://github.com/a")!))
        #expect(session.choose(row: 9) == .none)
    }

    // MARK: Esc

    @Test func escapeFirstClosesTheListThenRestoresTheAddressThenEndsEditing() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "github", byDeleting: false)
        session.moveSelection(by: 1)

        #expect(session.escape() == .none)
        #expect(!session.isListVisible)
        #expect(session.fieldText == "github")

        #expect(session.escape() == .none)
        #expect(session.fieldText == "https://current.example.com/")

        #expect(session.escape() == .endEditing)
    }

    /// On the Empty Page there is no address to go back to: the second step clears the field.
    @Test func onTheEmptyPageTheSecondStepClears() {
        let session = session(original: "", [candidate("https://github.com/a")])
        session.textChanged(to: "github", byDeleting: false)

        #expect(session.escape() == .none)
        #expect(session.escape() == .none)
        #expect(session.fieldText == "")
        #expect(session.escape() == .endEditing)
    }

    /// A step with nothing to do is skipped.
    @Test(arguments: [
        (typed: nil as String?, escapesToEnd: 1),
        (typed: "https://current.example.com/", escapesToEnd: 2),
    ])
    func stepsWithNothingToDoAreSkipped(_ row: (typed: String?, escapesToEnd: Int)) {
        let session = session()
        if let typed = row.typed { session.textChanged(to: typed, byDeleting: false) }

        var escapes = 1
        while session.escape() != .endEditing, escapes < 5 { escapes += 1 }

        #expect(escapes == row.escapesToEnd)
    }

    /// Typing again after Esc closed the list opens it again.
    @Test func typingAfterEscapeShowsTheListAgain() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "github", byDeleting: false)
        _ = session.escape()

        session.textChanged(to: "github.", byDeleting: false)

        #expect(session.isListVisible)
    }
}
