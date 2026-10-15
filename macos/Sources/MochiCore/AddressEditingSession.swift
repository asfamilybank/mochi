import Foundation

/// A page the address bar may suggest (#122): one address, with what the history knows about it —
/// already counted together across its visits, so the same address never comes twice.
public struct AddressSuggestionCandidate: Equatable, Sendable {
    public let url: URL
    /// The title of the latest visit that had one.
    public let title: String?
    public let faviconID: String?
    public let lastVisitedAt: Date
    /// How often and how lately the address was visited — recent visits weigh more
    /// (`HistoryStore.suggestionCandidates`).
    public let frecency: Double

    public init(url: URL, title: String?, faviconID: String?, lastVisitedAt: Date, frecency: Double) {
        self.url = url
        self.title = title
        self.faviconID = faviconID
        self.lastVisitedAt = lastVisitedAt
        self.frecency = frecency
    }
}

/// A page row in the suggestion list.
public struct AddressSuggestionPage: Equatable, Sendable {
    public let url: URL
    public let title: String?
    public let faviconID: String?

    public init(url: URL, title: String?, faviconID: String?) {
        self.url = url
        self.title = title
        self.faviconID = faviconID
    }
}

/// One row of the list under the address bar.
public enum AddressSuggestionRow: Equatable, Sendable {
    /// The first row when Return opens an address: 「打开 github.com」.
    case open(URL)
    /// The first row when Return searches: 「用 Google 搜索 “git”」.
    case search(query: String, engine: SearchEngine)
    /// A page from history.
    case page(AddressSuggestionPage)
}

/// What a key or click in the address bar comes to.
public enum AddressEditingOutcome: Equatable, Sendable {
    case none
    case navigate(URL)
    /// Leave the field, putting the page's title or address back.
    case endEditing
}

/// One stretch of editing in the Smart Address Field (#122, ADR-0034): from the click (or ⌘L)
/// that puts the address up for editing, to Return, Esc or a blur. It owns what the field shows
/// and the list under it; the AppKit view only feeds it keys and draws what it says.
///
/// - The list opens once something is typed. Its first row is always what Return would do with
///   the text — open it as an address, or search it — and below come up to seven pages from
///   history whose address or title has a word starting with each word typed (`https://` and
///   `www.` aside), the more frecent first.
/// - ↑↓ move through the list, and the field shows the selected page's address; Return opens the
///   selection, a click opens the row clicked.
/// - Esc takes three steps, skipping any with nothing to do: close the list, keeping what was
///   typed; put the page's address back (on the Empty Page, clear the field); leave the field.
///
/// Suggestions come only from what is on this Mac — nothing typed leaves it before Return.
public final class AddressEditingSession {
    /// Rows in the list, the first among them.
    public static let maximumRows = 8

    /// What the field showed when editing began — the page's address, or nothing on the Empty Page.
    public let originalText: String
    private let searchEngine: SearchEngine
    /// Asked on every change of what is typed, with the words typed (lowercased, `https://` and
    /// `www.` taken off): the store narrows its candidates by them; the exact rule is applied here.
    private let candidates: ([String]) -> [AddressSuggestionCandidate]

    /// What the field shows.
    public private(set) var fieldText: String
    public private(set) var isListVisible = false
    public private(set) var rows: [AddressSuggestionRow] = []
    /// The highlighted row while the list is up; the first row unless ↑↓ moved it.
    public private(set) var selectedIndex: Int?
    /// What the user typed, which `fieldText` leaves when ↑↓ show another row's address.
    private var typedText: String
    /// Where Return goes when the first row is selected.
    private var firstRowTarget: URL?

    public init(
        originalText: String, searchEngine: SearchEngine,
        candidates: @escaping ([String]) -> [AddressSuggestionCandidate]
    ) {
        self.originalText = originalText
        self.searchEngine = searchEngine
        self.candidates = candidates
        fieldText = originalText
        typedText = originalText
    }

    // MARK: Events

    /// The user changed the text — typing (`byDeleting` false) or deleting.
    public func textChanged(to text: String, byDeleting: Bool) {
        typedText = text
        fieldText = text
        guard let meaning = AddressInput.interpret(text, searchEngine: searchEngine) else {
            closeList()
            return
        }
        let firstRow: AddressSuggestionRow =
            switch meaning {
            case .address(let url): .open(url)
            case .search(let query, _): .search(query: query, engine: searchEngine)
            }
        firstRowTarget = meaning.url
        let words = Self.words(in: text)
        let pages = Self.rank(candidates(words).filter { Self.matches($0, words: words) })
            .prefix(Self.maximumRows - 1)
            .map { AddressSuggestionRow.page(AddressSuggestionPage(url: $0.url, title: $0.title, faviconID: $0.faviconID)) }
        rows = [firstRow] + pages
        selectedIndex = 0
        isListVisible = true
    }

    /// ↑ (`-1`) or ↓ (`+1`), staying within the list. The field follows the selection: a page's
    /// address, or back to what was typed on the first row.
    public func moveSelection(by delta: Int) {
        guard isListVisible, let selectedIndex else { return }
        let index = min(max(selectedIndex + delta, 0), rows.count - 1)
        self.selectedIndex = index
        fieldText = target(ofRow: index).flatMap { index == 0 ? nil : $0.absoluteString } ?? typedText
    }

    /// Return: the selected row, or — with the list closed — whatever the field holds.
    public func enter() -> AddressEditingOutcome {
        if isListVisible, let selectedIndex, let url = target(ofRow: selectedIndex) {
            return .navigate(url)
        }
        return AddressInput.resolve(fieldText, searchEngine: searchEngine).map(AddressEditingOutcome.navigate) ?? .none
    }

    /// A click on row `index`.
    public func choose(row index: Int) -> AddressEditingOutcome {
        guard isListVisible, let url = target(ofRow: index) else { return .none }
        return .navigate(url)
    }

    /// Esc, one step at a time.
    public func escape() -> AddressEditingOutcome {
        if isListVisible {
            fieldText = typedText
            closeList()
            return .none
        }
        if fieldText != originalText {
            fieldText = originalText
            typedText = originalText
            return .none
        }
        return .endEditing
    }

    // MARK: - Rows

    private func closeList() {
        isListVisible = false
        rows = []
        selectedIndex = nil
        firstRowTarget = nil
    }

    private func target(ofRow index: Int) -> URL? {
        guard rows.indices.contains(index) else { return nil }
        switch rows[index] {
        case .open, .search: return firstRowTarget
        case .page(let page): return page.url
        }
    }

    /// The more frecent first, then the more recently visited; each address once.
    private static func rank(_ candidates: [AddressSuggestionCandidate]) -> [AddressSuggestionCandidate] {
        var seen: Set<URL> = []
        return candidates
            .sorted { ($0.frecency, $0.lastVisitedAt) > ($1.frecency, $1.lastVisitedAt) }
            .filter { seen.insert($0.url).inserted }
    }

    // MARK: - Matching

    /// The words typed, lowercased, each without a leading `https://`/`http://` or `www.` — the
    /// parts of an address that every address shares and so tell nothing apart.
    static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map { stripCommonPrefixes(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func stripCommonPrefixes(_ text: String) -> String {
        var text = Substring(text)
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = text.dropFirst(scheme.count)
        }
        if text.hasPrefix("www.") { text = text.dropFirst(4) }
        return String(text)
    }

    /// Every word typed starts a word of the address (without its scheme and `www.`) or the title.
    private static func matches(_ candidate: AddressSuggestionCandidate, words: [String]) -> Bool {
        let address = stripCommonPrefixes(candidate.url.absoluteString.lowercased())
        let title = candidate.title?.lowercased() ?? ""
        return words.allSatisfy { startsAWord($0, in: address) || startsAWord($0, in: title) }
    }

    /// Whether `word` occurs in `text` where a word begins: at the start, after anything that isn't
    /// a latin letter or digit, or anywhere when it doesn't itself begin with one — CJK has no
    /// spaces, so any character there can begin a word.
    private static func startsAWord(_ word: String, in text: String) -> Bool {
        guard let first = word.first else { return true }
        let beginsLatin = isLatinAlphanumeric(first)
        var searchStart = text.startIndex
        while let found = text.range(of: word, range: searchStart..<text.endIndex) {
            if !beginsLatin || found.lowerBound == text.startIndex
                || !isLatinAlphanumeric(text[text.index(before: found.lowerBound)])
            {
                return true
            }
            searchStart = text.index(after: found.lowerBound)
        }
        return false
    }

    private static func isLatinAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
