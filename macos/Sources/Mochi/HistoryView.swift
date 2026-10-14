import Combine
import MochiCore
import SwiftUI

/// Adapts `HistoryBrowser` (MochiCore) to SwiftUI, the way `SettingsViewModel` adapts
/// `SettingsController`: `days` and `results` are published copies of the browser's state, taken
/// after everything that changes it, never a second source of truth.
final class HistoryViewModel: ObservableObject {
    private let browser: HistoryBrowser

    /// The toolbar's search field (`HistoryWindowController`). Typing is searched once it pauses
    /// for `searchDelay` (#118), so a burst of keystrokes is one search rather than one each;
    /// emptying the field goes back to the timeline at once.
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            pendingSearch?.cancel()
            let isBlank = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let search = DispatchWorkItem { [weak self] in self?.search() }
            pendingSearch = search
            DispatchQueue.main.asyncAfter(deadline: .now() + (isBlank ? 0 : Self.searchDelay), execute: search)
        }
    }
    private static let searchDelay: TimeInterval = 0.15
    private var pendingSearch: DispatchWorkItem?
    @Published var selection: Set<HistoryVisit.ID> = []
    /// The timeline (#116), while not searching.
    @Published private(set) var days: [HistoryBrowser.Day] = []
    /// The search results, while searching (#118).
    @Published private(set) var results: [HistoryBrowser.Row] = []
    @Published private(set) var isSearching = false
    /// 「N 个匹配项」, shown in the toolbar in 清除历史记录…'s place while searching.
    @Published private(set) var matchCount = 0
    /// The search as it was run, for the 没有找到结果 page to say what wasn't found.
    @Published private(set) var searchTerms = HistoryBrowser.SearchTerms(host: nil, text: "")
    /// 清除历史记录… is showing (ADR-0032) — set by the toolbar button.
    @Published var isClearingHistory = false
    private let icons: HistoryFaviconImages

    init(browser: HistoryBrowser) {
        self.browser = browser
        icons = HistoryFaviconImages(png: browser.favicon)
        // Nothing is read yet: the window controller removes what has expired, then resets the
        // folding, as the window opens.
    }

    /// Re-reads the store, keeping what is unfolded — each time the window comes forward (visits
    /// made while it was in the back show up then).
    func reload() {
        browser.reload()
        publish()
    }

    /// Back to today alone unfolded (#116) — each time ⌘Y opens the window.
    func resetExpansion() {
        browser.resetExpansion()
        publish()
    }

    private func search() {
        pendingSearch = nil
        browser.search(query)
        publish()
    }

    func setExpanded(_ isExpanded: Bool, day: Date) {
        browser.setExpanded(isExpanded, day: day)
        publish()
    }

    /// Copies the browser's state out. A selection that is no longer on show — deleted, or folded
    /// away — is dropped, so Delete never reaches a visit that isn't on screen.
    private func publish() {
        days = browser.days
        results = browser.results
        isSearching = browser.isSearching
        matchCount = browser.matchCount
        searchTerms = browser.searchTerms
        let shown = Set(browser.shownRows.map(\.id))
        if !selection.isSubset(of: shown) { selection.formIntersection(shown) }
    }

    /// #110 — the caller reloads afterwards.
    func removeExpiredVisits() {
        browser.removeExpiredVisits()
    }

    func delete(_ visits: Set<HistoryVisit.ID>) {
        guard !visits.isEmpty else { return }
        browser.delete(visits)
        publish()
    }

    func deleteDay(_ day: Date) {
        browser.deleteDay(day)
        publish()
    }

    func open(_ visits: Set<HistoryVisit.ID>) {
        browser.open(visits)
    }

    /// 拷贝 / ⌘C (#119): the whole address of one visit; `nil` with several selected.
    func copiedText(_ visits: Set<HistoryVisit.ID>) -> String? {
        browser.copiedText(for: visits)
    }

    func canCopy(_ visits: Set<HistoryVisit.ID>) -> Bool {
        copiedText(visits) != nil
    }

    func copy(_ visits: Set<HistoryVisit.ID>) {
        guard let text = copiedText(visits) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func canShowSite(_ visits: Set<HistoryVisit.ID>) -> Bool {
        browser.siteQuery(for: visits) != nil
    }

    /// 显示此网站的所有记录 (#119): searches `site:<host>` at once, and the toolbar's field shows it.
    func showSite(_ visits: Set<HistoryVisit.ID>) {
        guard let siteQuery = browser.siteQuery(for: visits) else { return }
        query = siteQuery
        pendingSearch?.cancel()
        search()
    }

    /// A row's site icon, `nil` when its visit has none (the row shows a placeholder).
    func icon(for row: HistoryBrowser.Row) -> NSImage? {
        icons.image(for: row.faviconID)
    }

    /// 清除历史记录…'s 清除: the visits within `range`, history alone; the list shows what is left
    /// at once.
    func clearHistory(from range: BrowsingDataTimeRange) {
        browser.clearHistory(from: range)
        publish()
    }
}

/// The 历史记录 window's content (#108; ADR-0018 — the window and its search field are AppKit).
/// A timeline of foldable days, newest first (#116), each header with its 「N 项」; search results
/// as one flat timeline (#118). Double-click opens a page in the widget; Delete or the context
/// menu removes the selection; a day's header has 删除这一天. With one row selected, the context
/// menu also copies its address (拷贝, ⌘C) and shows every visit to its host (显示此网站的所有记录,
/// #119). The toolbar's 清除历史记录… asks for a time range and clears history alone, over this
/// window (ADR-0032).
struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel

    var body: some View {
        Group {
            if model.isSearching ? model.results.isEmpty : model.days.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(minWidth: 420, minHeight: 280)
        .sheet(isPresented: $model.isClearingHistory) {
            ClearHistorySheet { range in model.clearHistory(from: range) }
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            if model.isSearching {
                rows(model.results)
            } else {
                // A day is a row of the list, not a section header, so folded days sit as close
                // together as any rows: macOS gives List sections their own spacing and has no
                // way to tighten it (`listSectionSpacing` is unavailable here). Its id is a
                // `Date`, not a visit's, so it can't be selected.
                ForEach(model.days) { day in
                    HistoryDayHeader(day: day) { model.setExpanded(!day.isExpanded, day: day.day) }
                        .contextMenu { deleteDayButton(day.day) }
                    if day.isExpanded { rows(day.rows) }
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: HistoryVisit.ID.self) { visits in
            if !visits.isEmpty {
                Button { model.open(visits) } label: { Label("打开", systemImage: "arrow.up.forward.app") }
                Button { model.copy(visits) } label: { Label("拷贝", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c")
                    .disabled(!model.canCopy(visits))
                Button { model.showSite(visits) } label: {
                    Label("显示此网站的所有记录", systemImage: "line.3.horizontal.decrease.circle")
                }
                .disabled(!model.canShowSite(visits))
                Divider()
                Button { model.delete(visits) } label: { Label("删除", systemImage: "trash") }
            }
        } primaryAction: { visits in
            model.open(visits)
        }
        .onDeleteCommand { model.delete(model.selection) }
        // ⌘C is `HistoryWindowController.copy(_:)`, not `onCopyCommand`: given nothing to copy,
        // that one still empties the pasteboard (#119).
    }

    private func rows(_ rows: [HistoryBrowser.Row]) -> some View {
        ForEach(rows) { row in
            HistoryRow(row: row, icon: model.icon(for: row))
        }
    }

    private func deleteDayButton(_ day: Date) -> some View {
        Button { model.deleteDay(day) } label: { Label("删除这一天", systemImage: "trash") }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.isSearching {
            ContentUnavailableView("没有历史记录", systemImage: "clock", description: Text("在窗口里访问过的网页会列在这里。"))
        } else {
            ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass", description: Text(noResultsDescription))
        }
    }

    /// What wasn't found — with `site:`, the host it was narrowed to (#118).
    private var noResultsDescription: String {
        let (host, text) = (model.searchTerms.host, model.searchTerms.text)
        switch (host, text.isEmpty) {
        case (let host?, true): return "没有来自 \(host) 的记录。"
        case (let host?, false): return "\(host) 上没有标题或网址包含“\(text)”的网页。"
        case (nil, _): return "没有标题或网址包含“\(text)”的网页。"
        }
    }
}

/// A day of the timeline (#116), after Chrome's: a row of its own that folds and unfolds the day
/// when clicked, the chevron turning to say which it is; how many visits it has on the right.
private struct HistoryDayHeader: View {
    let day: HistoryBrowser.Day
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(day.isExpanded ? 90 : 0))
                    .frame(width: 12)
                Text(day.title)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text("\(day.visits) 项")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.title)
        .accessibilityValue(day.isExpanded ? "已展开，\(day.visits) 项" : "已折叠，\(day.visits) 项")
    }
}

private struct HistoryRow: View {
    let row: HistoryBrowser.Row
    /// The visit's own site icon (#117); a globe stands in when it has none.
    let icon: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            // Decoration: the title and address say which page it is.
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Text(row.time)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .help(row.url.absoluteString)
    }
}
