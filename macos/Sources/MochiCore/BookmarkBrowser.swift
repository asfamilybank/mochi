import Foundation

/// Why the 书签 window couldn't save what was typed (#123).
public enum BookmarkEditError: Error, Equatable, Sendable {
    /// The address bar would search it, or open it somewhere other than the web.
    case notAnAddress
    /// Another bookmark already has the address — one bookmark per address.
    case alreadyBookmarked(Bookmark.ID)
    /// The database refused the write.
    case notSaved
}

/// The 书签 window's state and what it does (#123, ADR-0033), kept out of the view so it can be
/// tested against a real store. The SwiftUI view only draws it.
///
/// Every bookmark in the user's order, or — while searching — those whose name or address
/// contains the query anywhere: the window is for finding a bookmark, so the address bar's
/// word-start rule (ADR-0034) doesn't apply here. Only the whole list can be reordered.
///
/// Addresses typed into it are read the way the address bar reads them, and only web pages are
/// kept. A new bookmark goes to the end of the list, with no icon until it is first visited.
public final class BookmarkBrowser {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: Bookmark.ID
        public let name: String
        public let url: URL
        public let faviconID: String?
    }

    private let store: BookmarkStore
    private let openInWidget: (URL) -> Void

    /// As typed.
    public private(set) var query = ""
    /// What is on show, top to bottom.
    public private(set) var rows: [Row] = []

    /// - Parameter open: `Orchestrator.openBookmark` — reopens a closed widget, leaves Ghost Mode
    ///   alone.
    public init(store: BookmarkStore, open: @escaping (URL) -> Void) {
        self.store = store
        openInWidget = open
    }

    public var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// Dragging rows reorders the list — not while it is filtered.
    public var canReorder: Bool {
        !isSearching
    }

    /// Re-reads the store, keeping the search.
    public func reload() {
        let all = store.all().map { Row(id: $0.id, name: $0.name, url: $0.url, faviconID: $0.faviconID) }
        let query = trimmedQuery.lowercased()
        rows = query.isEmpty
            ? all
            : all.filter { $0.name.lowercased().contains(query) || $0.url.absoluteString.lowercased().contains(query) }
    }

    public func search(_ query: String) {
        self.query = query
        reload()
    }

    /// A drag of the rows at `offsets` to before the row at `destination` (SwiftUI's `onMove`).
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard canReorder else { return }
        var order = rows.map(\.id)
        order.move(fromOffsets: offsets, toOffset: destination)
        store.setOrder(order)
        reload()
    }

    public func delete(_ ids: Set<Bookmark.ID>) {
        guard !ids.isEmpty else { return }
        store.delete(ids)
        reload()
    }

    /// 新建书签: at the end of the list, named `name` — or its address, when blank.
    public func add(name: String, address: String) -> Result<Bookmark.ID, BookmarkEditError> {
        guard let url = Self.webAddress(address) else { return .failure(.notAnAddress) }
        switch store.add(name: Self.name(name, orAddress: url), url: url) {
        case .success(let bookmark):
            reload()
            return .success(bookmark.id)
        case .failure(.alreadyBookmarked(let existing)):
            return .failure(.alreadyBookmarked(existing.id))
        case .failure(.notSaved):
            return .failure(.notSaved)
        }
    }

    /// 编辑: the name and address of `id`, in its place in the list, keeping its icon. `nil` when
    /// saved.
    public func edit(_ id: Bookmark.ID, name: String, address: String) -> BookmarkEditError? {
        guard let url = Self.webAddress(address) else { return .notAnAddress }
        if case .alreadyBookmarked(let other) = store.changeURL(id, to: url) { return .alreadyBookmarked(other.id) }
        store.rename(id, to: Self.name(name, orAddress: url))
        reload()
        return nil
    }

    /// The widget shows one page, so one bookmark at a time.
    public func canOpen(_ ids: Set<Bookmark.ID>) -> Bool {
        row(for: ids) != nil
    }

    public func open(_ ids: Set<Bookmark.ID>) {
        guard let row = row(for: ids) else { return }
        openInWidget(row.url)
    }

    /// 拷贝 / ⌘C: the address of one bookmark; `nil` with several selected.
    public func copiedText(for ids: Set<Bookmark.ID>) -> String? {
        row(for: ids)?.url.absoluteString
    }

    public func favicon(_ id: String) -> Data? {
        store.favicon(id)
    }

    // MARK: - Private

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func row(for ids: Set<Bookmark.ID>) -> Row? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return rows.first { $0.id == id }
    }

    /// `text` as the address bar would open it, when that is a web page.
    private static func webAddress(_ text: String) -> URL? {
        guard case .address(let url) = AddressInput.interpret(text, searchEngine: .google),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private static func name(_ name: String, orAddress url: URL) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url.absoluteString : trimmed
    }
}
