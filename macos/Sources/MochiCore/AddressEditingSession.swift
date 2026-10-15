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
    /// (`HistoryStore.suggestionCandidates`). `0` for a bookmark never visited.
    public let frecency: Double
    /// The bookmark's name when the address is one (#125) — shown in place of the page's title.
    public let bookmarkName: String?

    public init(
        url: URL, title: String?, faviconID: String?, lastVisitedAt: Date, frecency: Double,
        bookmarkName: String? = nil
    ) {
        self.url = url
        self.title = title
        self.faviconID = faviconID
        self.lastVisitedAt = lastVisitedAt
        self.frecency = frecency
        self.bookmarkName = bookmarkName
    }

    /// The same address, now known to be a bookmark named `name`.
    public func bookmarked(as name: String) -> AddressSuggestionCandidate {
        AddressSuggestionCandidate(
            url: url, title: title, faviconID: faviconID, lastVisitedAt: lastVisitedAt, frecency: frecency,
            bookmarkName: name)
    }
}

/// A page row in the suggestion list.
public struct AddressSuggestionPage: Equatable, Sendable {
    public let url: URL
    /// The bookmark's name for a bookmark, the page's title otherwise.
    public let title: String?
    public let faviconID: String?
    /// Marked as a bookmark in the list (#125).
    public let isBookmark: Bool

    public init(url: URL, title: String?, faviconID: String?, isBookmark: Bool = false) {
        self.url = url
        self.title = title
        self.faviconID = faviconID
        self.isBookmark = isBookmark
    }

    init(_ candidate: AddressSuggestionCandidate) {
        self.init(
            url: candidate.url, title: candidate.bookmarkName ?? candidate.title, faviconID: candidate.faviconID,
            isBookmark: candidate.bookmarkName != nil)
    }
}

/// One row of the list under the address bar.
public enum AddressSuggestionRow: Equatable, Sendable {
    /// The first row when Return opens an address: 「打开 github.com」.
    case open(URL)
    /// The first row when Return searches: 「用 Google 搜索 “git”」.
    case search(query: String, engine: SearchEngine)
    /// A page from history, or a bookmark.
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
/// - Inline completion (#124): the best-ranked page whose address (`https://`, `www.` aside)
///   starts with what was typed is completed in the field, the added part selected so typing on
///   replaces it; the first row then opens that page. Never after a deletion — until the next
///   character typed — and never for a search.
/// - ↑↓ move through the list, and the field shows the selected page's address; Return opens the
///   selection, a click opens the row clicked.
/// - Esc takes three steps, skipping any with nothing to do: close the list, keeping what was
///   typed; put the page's address back (on the Empty Page, clear the field); leave the field.
/// - Bookmarks (#125): before anything is typed, the list is every bookmark in the user's order,
///   nothing selected. Once typing, bookmarks are matched by their name as well, rank above pages
///   visited about as often, and show their name with a bookmark mark.
///
/// Suggestions come only from what is on this Mac — nothing typed leaves it before Return.
public final class AddressEditingSession {
    /// Rows in the list while typing, the first among them. The bookmarks listed before typing
    /// are all listed, and the list scrolls.
    public static let maximumRows = 8
    /// What being a bookmark adds to a page's frecency: more than one visit this week.
    static let bookmarkBonus: Double = 150

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
    /// The completed part of `fieldText`, in UTF-16 units — what the field selects (#124).
    public var completionRange: NSRange? {
        guard let inlineCompletion, fieldText == typedText + inlineCompletion else { return nil }
        return NSRange(location: (typedText as NSString).length, length: (inlineCompletion as NSString).length)
    }
    /// What the field shows after what was typed, completing it to `completedURL`.
    private var inlineCompletion: String?
    /// What the user typed, which `fieldText` leaves when ↑↓ show another row's address.
    private var typedText: String
    /// Where Return goes when the first row is selected.
    private var firstRowTarget: URL?

    /// - Parameter bookmarks: every bookmark, in the user's order — listed until something is
    ///   typed.
    public init(
        originalText: String, searchEngine: SearchEngine, bookmarks: [AddressSuggestionCandidate] = [],
        candidates: @escaping ([String]) -> [AddressSuggestionCandidate]
    ) {
        self.originalText = originalText
        self.searchEngine = searchEngine
        self.candidates = candidates
        fieldText = originalText
        typedText = originalText
        if !bookmarks.isEmpty {
            rows = bookmarks.map { .page(AddressSuggestionPage($0)) }
            isListVisible = true
        }
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
        var ranked = Self.rank(candidates(words).filter { Self.matches($0, words: words) })
        inlineCompletion = nil
        if !byDeleting, let (completed, suffix) = Self.completion(of: text, from: ranked) {
            inlineCompletion = suffix
            fieldText = text + suffix
            firstRowTarget = completed.url
            ranked.removeAll { $0.url == completed.url }
        }
        let pages = ranked.prefix(Self.maximumRows - 1).map { AddressSuggestionRow.page(AddressSuggestionPage($0)) }
        rows = [inlineCompletion == nil ? firstRow : .open(firstRowTarget ?? meaning.url)] + pages
        selectedIndex = 0
        isListVisible = true
    }

    /// ↑ (`-1`) or ↓ (`+1`), staying within the list. The field follows the selection: a page's
    /// address, or back to what was typed on the first row.
    public func moveSelection(by delta: Int) {
        guard isListVisible, !rows.isEmpty else { return }
        let index = min(max((selectedIndex ?? -1) + delta, 0), rows.count - 1)
        selectedIndex = index
        if case .page(let page) = rows[index] {
            fieldText = page.url.absoluteString
        } else {
            fieldText = typedText + (inlineCompletion ?? "")
        }
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
        if isListVisible || inlineCompletion != nil {
            fieldText = typedText
            inlineCompletion = nil
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

    /// The more frecent first — a bookmark counting `bookmarkBonus` more — then the more recently
    /// visited; each address once.
    private static func rank(_ candidates: [AddressSuggestionCandidate]) -> [AddressSuggestionCandidate] {
        var seen: Set<URL> = []
        func score(_ candidate: AddressSuggestionCandidate) -> Double {
            candidate.frecency + (candidate.bookmarkName == nil ? 0 : bookmarkBonus)
        }
        return candidates
            .sorted { (score($0), $0.lastVisitedAt) > (score($1), $1.lastVisitedAt) }
            .filter { seen.insert($0.url).inserted }
    }

    // MARK: - Completion

    /// The best-ranked candidate whose address — shown without `https://`, `www.` or a bare
    /// host's trailing `/` — starts with `text` (itself without `https://`/`www.`), and what of
    /// that address follows `text`. Nothing for text with whitespace in it: that is a search.
    private static func completion(of text: String, from ranked: [AddressSuggestionCandidate])
        -> (AddressSuggestionCandidate, String)?
    {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let typed = stripCommonPrefixes(text.lowercased())
        guard !typed.isEmpty else { return nil }
        for candidate in ranked {
            let shown = completionText(of: candidate.url)
            guard shown.lowercased().hasPrefix(typed), shown.count > typed.count else { continue }
            return (candidate, String(shown.dropFirst(typed.count)))
        }
        return nil
    }

    private static func completionText(of url: URL) -> String {
        var text = stripCommonPrefixes(url.absoluteString)
        if (url.path == "/" || url.path.isEmpty), url.query == nil, url.fragment == nil, text.hasSuffix("/") {
            text.removeLast()
        }
        return text
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
        for scheme in ["https://", "http://"] where text.lowercased().hasPrefix(scheme) {
            text = text.dropFirst(scheme.count)
        }
        if text.lowercased().hasPrefix("www.") { text = text.dropFirst(4) }
        return String(text)
    }

    /// Every word typed starts a word of the address (without its scheme and `www.`), the title
    /// or the bookmark's name.
    private static func matches(_ candidate: AddressSuggestionCandidate, words: [String]) -> Bool {
        let texts = [
            stripCommonPrefixes(candidate.url.absoluteString.lowercased()), candidate.title?.lowercased() ?? "",
            candidate.bookmarkName?.lowercased() ?? "",
        ]
        return words.allSatisfy { word in texts.contains { startsAWord(word, in: $0) } }
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
