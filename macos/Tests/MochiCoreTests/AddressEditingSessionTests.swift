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

    /// Every page suggested: the one completed in the field (#124), then the list's.
    private func suggested(_ session: AddressEditingSession) -> [String] {
        let completed: [String] =
            if session.completionRange != nil, case .open(let url)? = session.rows.first { [url.absoluteString] } else { [] }
        return completed + pages(session)
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

        #expect(suggested(session) == (row.matches ? ["https://www.github.com/asfamilybank/mochi"] : []))
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

        session.textChanged(to: "com", byDeleting: false)

        #expect(pages(session) == ["https://github.com/b", "https://github.com/c", "https://github.com/a"])
    }

    @Test func onEqualFrecencyTheLatestVisitComesFirst() {
        let session = session([
            candidate("https://github.com/a", visited: "2026-10-11 09:00"),
            candidate("https://github.com/b", visited: "2026-10-12 09:00"),
        ])

        session.textChanged(to: "com", byDeleting: false)

        #expect(pages(session) == ["https://github.com/b", "https://github.com/a"])
    }

    /// Eight rows at most, the first among them.
    @Test func theListHoldsEightRowsAtMost() {
        let session = session((0..<20).map { candidate("https://github.com/\($0)", frecency: Double(100 - $0)) })

        session.textChanged(to: "com", byDeleting: false)

        #expect(session.rows.count == 8)
        #expect(pages(session) == (0..<7).map { "https://github.com/\($0)" })
    }

    @Test func eachAddressIsListedOnce() {
        let session = session([candidate("https://github.com/"), candidate("https://github.com/")])

        session.textChanged(to: "com", byDeleting: false)

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
        session.textChanged(to: "com", byDeleting: false)

        session.moveSelection(by: 1)
        #expect(session.selectedIndex == 1)
        #expect(session.fieldText == "https://github.com/a")
        session.moveSelection(by: 1)
        #expect(session.fieldText == "https://github.com/b")

        #expect(session.enter() == .navigate(URL(string: "https://github.com/b")!))
    }

    @Test func movingBackToTheFirstRowPutsTheTypedTextBack() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "com", byDeleting: false)
        session.moveSelection(by: 1)

        session.moveSelection(by: -1)

        #expect(session.selectedIndex == 0)
        #expect(session.fieldText == "com")
    }

    @Test func theSelectionStaysWithinTheList() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "com", byDeleting: false)

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
        // Listed by its title alone, so nothing is completed (#124).
        let session = session([candidate("https://example.com/a", title: "github.com git")])
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
        session.textChanged(to: "com", byDeleting: false)

        #expect(session.choose(row: 1) == .navigate(URL(string: "https://github.com/a")!))
        #expect(session.choose(row: 9) == .none)
    }

    // MARK: Esc

    @Test func escapeFirstClosesTheListThenRestoresTheAddressThenEndsEditing() {
        let session = session([candidate("https://github.com/a")])
        session.textChanged(to: "com", byDeleting: false)
        session.moveSelection(by: 1)

        #expect(session.escape() == .none)
        #expect(!session.isListVisible)
        #expect(session.fieldText == "com")

        #expect(session.escape() == .none)
        #expect(session.fieldText == "https://current.example.com/")

        #expect(session.escape() == .endEditing)
    }

    /// On the Empty Page there is no address to go back to: the second step clears the field.
    @Test func onTheEmptyPageTheSecondStepClears() {
        let session = session(original: "", [candidate("https://github.com/a")])
        session.textChanged(to: "com", byDeleting: false)

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
        session.textChanged(to: "com", byDeleting: false)
        _ = session.escape()

        session.textChanged(to: "com.", byDeleting: false)

        #expect(session.isListVisible)
    }

    // MARK: Inline completion (#124)

    /// The part the field shows beyond what was typed — selected, so typing on replaces it.
    private func completion(_ session: AddressEditingSession) -> String? {
        guard let range = session.completionRange else { return nil }
        return (session.fieldText as NSString).substring(with: range)
    }

    @Test func theLikeliestAddressIsCompletedInTheField() {
        let session = session([candidate("https://github.com/", title: "GitHub")])

        session.textChanged(to: "git", byDeleting: false)

        #expect(session.fieldText == "github.com")
        #expect(completion(session) == "hub.com")
        #expect(session.rows.first == .open(URL(string: "https://github.com/")!))
        #expect(session.enter() == .navigate(URL(string: "https://github.com/")!))
    }

    /// The completed page is the first row; it isn't listed again below.
    @Test func theCompletedPageIsNotListedTwice() {
        let session = session([candidate("https://github.com/"), candidate("https://github.com/explore", frecency: 50)])

        session.textChanged(to: "git", byDeleting: false)

        #expect(pages(session) == ["https://github.com/explore"])
    }

    /// The likeliest address *starting with* what was typed, even when a page matched only by
    /// its title ranks above it (ADR-0034 accepts completing a deep page).
    @Test func theCompletionIsTheBestRankedAddressThatStartsWithTheText() {
        let session = session([
            candidate("https://liaoxuefeng.com/wiki/git", title: "Git 教程", frecency: 500),
            candidate("https://github.com/asfamilybank/mochi", frecency: 300),
            candidate("https://github.com/", frecency: 100),
        ])

        session.textChanged(to: "git", byDeleting: false)

        #expect(session.fieldText == "github.com/asfamilybank/mochi")
        #expect(pages(session) == ["https://liaoxuefeng.com/wiki/git", "https://github.com/"])
    }

    @Test(arguments: [
        (typed: "https://git", field: "https://github.com"),
        (typed: "www.git", field: "www.github.com"),
        (typed: "GIT", field: "GIThub.com"),
        (typed: "github.com/", field: "github.com/"),
    ])
    func whatWasTypedIsKeptAsTyped(_ row: (typed: String, field: String)) {
        let session = session([candidate("https://www.github.com/")])

        session.textChanged(to: row.typed, byDeleting: false)

        #expect(session.fieldText == row.field)
    }

    @Test func nothingIsCompletedWithoutAnAddressStartingWithTheText() {
        let session = session([candidate("https://example.com/", title: "Git 教程")])

        session.textChanged(to: "git", byDeleting: false)

        #expect(session.fieldText == "git")
        #expect(session.completionRange == nil)
        #expect(session.rows.first == .search(query: "git", engine: .google))
    }

    /// Typing on keeps the completion while it still fits, and drops it once it doesn't.
    @Test func typingOnKeepsTheCompletionOnlyWhileItFits() {
        let session = session([candidate("https://github.com/")])
        session.textChanged(to: "git", byDeleting: false)

        session.textChanged(to: "gith", byDeleting: false)
        #expect(session.fieldText == "github.com")

        session.textChanged(to: "githx", byDeleting: false)
        #expect(session.fieldText == "githx")
        #expect(session.completionRange == nil)
    }

    /// Deleting must be able to take the completed part away — it isn't put straight back.
    @Test func deletingCompletesNothingUntilTheNextCharacterTyped() {
        let session = session([candidate("https://github.com/")])
        session.textChanged(to: "gith", byDeleting: false)

        session.textChanged(to: "gith", byDeleting: true)
        #expect(session.fieldText == "gith")
        #expect(session.completionRange == nil)
        #expect(session.rows.first == .search(query: "gith", engine: .google))

        session.textChanged(to: "githu", byDeleting: false)
        #expect(session.fieldText == "github.com")
    }

    @Test func aSearchIsNeverCompleted() {
        let session = session([candidate("https://github.com/")])

        session.textChanged(to: "git hub", byDeleting: false)

        #expect(session.fieldText == "git hub")
        #expect(session.completionRange == nil)
    }

    @Test func theFirstEscapeTakesTheCompletionAway() {
        let session = session([candidate("https://github.com/")])
        session.textChanged(to: "git", byDeleting: false)

        #expect(session.escape() == .none)

        #expect(session.fieldText == "git")
        #expect(session.completionRange == nil)
        #expect(session.enter() == .navigate(URL(string: "https://www.google.com/search?q=git")!))
    }

    @Test func movingBackToTheFirstRowBringsTheCompletionBack() {
        let session = session([candidate("https://github.com/"), candidate("https://github.com/explore", frecency: 50)])
        session.textChanged(to: "git", byDeleting: false)

        session.moveSelection(by: 1)
        #expect(session.completionRange == nil)
        session.moveSelection(by: -1)

        #expect(session.fieldText == "github.com")
        #expect(completion(session) == "hub.com")
    }
}
