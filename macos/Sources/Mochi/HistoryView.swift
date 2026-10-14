import Combine
import MochiCore
import SwiftUI

/// Adapts `HistoryBrowser` (MochiCore) to SwiftUI, the way `SettingsViewModel` adapts
/// `SettingsController`: `sections` is a published copy re-read from the store after every
/// search and deletion, never a second source of truth.
final class HistoryViewModel: ObservableObject {
    private let browser: HistoryBrowser
    private let clearBrowsingData: (Set<BrowsingDataKind>, BrowsingDataTimeRange) -> Void

    /// The toolbar's search field (`HistoryWindowController`).
    @Published var query = "" {
        didSet { if query != oldValue { reload() } }
    }
    @Published var selection: Set<HistoryVisit.ID> = []
    @Published private(set) var sections: [HistoryBrowser.Section] = []
    /// 清除历史记录… is showing (#115) — set by the toolbar button.
    @Published var isClearingHistory = false

    init(
        browser: HistoryBrowser,
        clearBrowsingData: @escaping (Set<BrowsingDataKind>, BrowsingDataTimeRange) -> Void
    ) {
        self.browser = browser
        self.clearBrowsingData = clearBrowsingData
        reload()
    }

    /// Re-reads the store — on every search and deletion, and each time the window comes forward
    /// (pages visited while it was in the back show up then). A selection that is no longer listed
    /// is dropped, so Delete never reaches a page that isn't on screen.
    func reload() {
        sections = browser.sections(matching: query)
        let shown = Set(sections.lazy.flatMap(\.rows).map(\.id))
        if !selection.isSubset(of: shown) { selection.formIntersection(shown) }
    }

    /// #110 — the caller reloads afterwards.
    func removeExpiredVisits() {
        browser.removeExpiredVisits()
    }

    func delete(_ visits: Set<HistoryVisit.ID>) {
        guard !visits.isEmpty else { return }
        browser.delete(visits)
        reload()
    }

    func deleteDay(_ day: Date) {
        browser.deleteDay(day)
        reload()
    }

    func open(_ visits: Set<HistoryVisit.ID>) {
        browser.open(visits, shownIn: sections)
    }

    /// 清除历史记录…'s 清除 — the very clearing the settings window's dialog does, then a re-read so
    /// what went is gone from the list at once.
    func clear(_ kinds: Set<BrowsingDataKind>, from range: BrowsingDataTimeRange) {
        clearBrowsingData(kinds, range)
        reload()
    }
}

/// The 历史记录 window's content (#108; ADR-0018 — the window and its search field are AppKit).
/// Grouped by day, newest first. Double-click opens a page in the widget; Delete or the context
/// menu removes the selection; a day's header has 删除这一天. The toolbar's 清除历史记录… shows the
/// settings window's 清除浏览数据 sheet here, over this window (#115).
struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel

    var body: some View {
        Group {
            if model.sections.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(minWidth: 420, minHeight: 280)
        .sheet(isPresented: $model.isClearingHistory) {
            ClearBrowsingDataSheet(initialKinds: [.history]) { kinds, range in model.clear(kinds, from: range) }
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        HistoryRow(row: row)
                    }
                } header: {
                    Text(section.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("删除这一天") { model.deleteDay(section.day) }
                        }
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: HistoryVisit.ID.self) { visits in
            if !visits.isEmpty {
                Button("打开") { model.open(visits) }
                Divider()
                Button("删除") { model.delete(visits) }
            }
        } primaryAction: { visits in
            model.open(visits)
        }
        .onDeleteCommand { model.delete(model.selection) }
    }

    @ViewBuilder private var emptyState: some View {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            ContentUnavailableView("没有历史记录", systemImage: "clock", description: Text("在窗口里访问过的网页会列在这里。"))
        } else {
            ContentUnavailableView(
                "没有找到结果", systemImage: "magnifyingglass", description: Text("没有标题或网址包含“\(query)”的网页。"))
        }
    }
}

private struct HistoryRow: View {
    let row: HistoryBrowser.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
            Spacer(minLength: 0)
            Text(row.time)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .help(row.url.absoluteString)
    }
}
