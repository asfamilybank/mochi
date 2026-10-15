import Combine
import MochiCore
import SwiftUI

/// Adapts `BookmarkBrowser` (MochiCore) to SwiftUI, the way `HistoryViewModel` adapts
/// `HistoryBrowser`: `rows` is a published copy of the browser's state, taken after everything
/// that changes it.
final class BookmarksViewModel: ObservableObject {
    private let browser: BookmarkBrowser

    /// The toolbar's search field (`BookmarksWindowController`).
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            browser.search(query)
            publish()
        }
    }
    @Published var selection: Set<Bookmark.ID> = []
    @Published private(set) var rows: [BookmarkBrowser.Row] = []
    @Published private(set) var canReorder = true
    @Published private(set) var isSearching = false
    /// The 新建书签/编辑 sheet, while it is up.
    @Published var form: BookmarkForm?
    private let icons: HistoryFaviconImages

    init(browser: BookmarkBrowser) {
        self.browser = browser
        icons = HistoryFaviconImages(png: browser.favicon)
    }

    /// Re-reads the store — each time the window comes forward, so a ⌘D made meanwhile shows.
    func reload() {
        browser.reload()
        publish()
    }

    /// A selection no longer on show is dropped, so Delete never reaches a hidden bookmark.
    private func publish() {
        rows = browser.rows
        canReorder = browser.canReorder
        isSearching = browser.isSearching
        let shown = Set(rows.map(\.id))
        if !selection.isSubset(of: shown) { selection.formIntersection(shown) }
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        browser.move(fromOffsets: offsets, toOffset: destination)
        publish()
    }

    func delete(_ ids: Set<Bookmark.ID>) {
        browser.delete(ids)
        publish()
    }

    func canOpen(_ ids: Set<Bookmark.ID>) -> Bool { browser.canOpen(ids) }
    func open(_ ids: Set<Bookmark.ID>) { browser.open(ids) }

    /// The row under the pointer — which one a double-click hit, when several are selected.
    var hoveredRow: Bookmark.ID?

    /// The list's primary action: Return opens the one selected bookmark; a double-click opens the
    /// row it hit (SwiftUI hands over the whole selection either way).
    func activate(_ ids: Set<Bookmark.ID>) {
        let event = NSApp.currentEvent
        let isDoubleClick = event.map { [.leftMouseDown, .leftMouseUp].contains($0.type) && $0.clickCount >= 2 } ?? false
        if isDoubleClick, let hit = hoveredRow, ids.contains(hit) {
            selection = [hit]
            open([hit])
        } else {
            open(ids)
        }
    }

    func canCopy(_ ids: Set<Bookmark.ID>) -> Bool { browser.copiedText(for: ids) != nil }

    func copy(_ ids: Set<Bookmark.ID>) {
        guard let text = browser.copiedText(for: ids) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func icon(for row: BookmarkBrowser.Row) -> NSImage? {
        icons.image(for: row.faviconID)
    }

    // MARK: 新建书签 / 编辑

    func beginAdding() {
        form = BookmarkForm(editing: nil, name: "", address: "")
    }

    func beginEditing(_ ids: Set<Bookmark.ID>) {
        guard ids.count == 1, let row = rows.first(where: { ids.contains($0.id) }) else { return }
        form = BookmarkForm(editing: row.id, name: row.name, address: row.url.absoluteString)
    }

    /// Saves the sheet's fields; on success the sheet closes, otherwise it says why and stays.
    func saveForm() {
        guard let form else { return }
        let error: BookmarkEditError?
        if let id = form.editing {
            error = browser.edit(id, name: form.name, address: form.address)
            if error == nil { selection = [id] }
        } else {
            switch browser.add(name: form.name, address: form.address) {
            case .success(let id):
                error = nil
                selection = [id]
            case .failure(let failure):
                error = failure
            }
        }
        publish()
        guard let error else {
            self.form = nil
            return
        }
        if case .alreadyBookmarked(let existing) = error, rows.contains(where: { $0.id == existing }) {
            selection = [existing]
        }
        self.form?.error = Self.message(for: error)
    }

    private static func message(for error: BookmarkEditError) -> String {
        switch error {
        case .notAnAddress: "请输入网页地址，例如 example.com。"
        case .alreadyBookmarked: "已存在：这个网址已经在书签里了。"
        case .notSaved: "没能存下书签，请再试一次。"
        }
    }
}

/// The fields of the 新建书签/编辑 sheet.
struct BookmarkForm {
    /// The bookmark being edited; `nil` for a new one.
    let editing: Bookmark.ID?
    var name: String
    var address: String
    /// Why the last 存储 didn't save.
    var error: String?
}

/// The 书签 window's content (#123; ADR-0018 — the window and its toolbar are AppKit): every
/// bookmark in the user's order, its name and address side by side. Drag to reorder (not while
/// searching), double-click or Return to open, Delete or the context menu to remove; the context
/// menu also opens, edits and copies one bookmark.
struct BookmarksView: View {
    @ObservedObject var model: BookmarksViewModel

    var body: some View {
        Group {
            if model.rows.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(minWidth: 460, minHeight: 280)
        .sheet(isPresented: Binding(get: { model.form != nil }, set: { if !$0 { model.form = nil } })) {
            BookmarkFormSheet(model: model)
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.rows) { row in
                BookmarkRow(row: row, icon: model.icon(for: row))
                    .onHover { isHovering in
                        if isHovering {
                            model.hoveredRow = row.id
                        } else if model.hoveredRow == row.id {
                            model.hoveredRow = nil
                        }
                    }
            }
            .onMove(perform: model.canReorder ? model.move : nil)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: Bookmark.ID.self) { ids in
            if !ids.isEmpty {
                Button { model.open(ids) } label: { Label("打开", systemImage: "arrow.up.forward.app") }
                    .disabled(!model.canOpen(ids))
                Button { model.beginEditing(ids) } label: { Label("编辑…", systemImage: "pencil") }
                    .disabled(ids.count != 1)
                Button { model.copy(ids) } label: { Label("拷贝", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c")
                    .disabled(!model.canCopy(ids))
                Divider()
                Button { model.delete(ids) } label: { Label("删除", systemImage: "trash") }
            }
        } primaryAction: { ids in
            model.activate(ids)
        }
        .onDeleteCommand { model.delete(model.selection) }
        // ⌘C is `BookmarksWindowController.copy(_:)`, as in the 历史记录 window (#119).
    }

    @ViewBuilder private var emptyState: some View {
        if model.isSearching {
            ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass", description: Text("没有名称或网址包含“\(model.query.trimmingCharacters(in: .whitespacesAndNewlines))”的书签。"))
        } else {
            ContentUnavailableView("没有书签", systemImage: "bookmark", description: Text("在网页上按 ⌘D，或点工具栏里的「新建书签」。"))
        }
    }
}

private struct BookmarkRow: View {
    let row: BookmarkBrowser.Row
    /// The bookmark's own site icon; a globe stands in when it has none.
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            // Decoration: the name and address say which bookmark it is.
            .accessibilityHidden(true)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.url.absoluteString)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(row.url.absoluteString)
    }
}

/// 新建书签 / 编辑: a name and an address; 存储 checks the address the way the address bar reads
/// it and says why when it can't keep it. Edits the model's form in place, so what 存储 reports
/// shows under the fields.
private struct BookmarkFormSheet: View {
    @ObservedObject var model: BookmarksViewModel

    private func field(_ keyPath: WritableKeyPath<BookmarkForm, String>) -> Binding<String> {
        Binding(get: { model.form?[keyPath: keyPath] ?? "" }, set: { model.form?[keyPath: keyPath] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.form?.editing == nil ? "新建书签" : "编辑书签")
                .font(.headline)
            Form {
                LabeledContent("名称") {
                    TextField("名称", text: field(\.name), prompt: Text("留空则使用网址"))
                        .labelsHidden()
                        .frame(width: 280)
                }
                LabeledContent("网址") {
                    TextField("网址", text: field(\.address), prompt: Text("example.com"))
                        .labelsHidden()
                        .frame(width: 280)
                }
            }
            .formStyle(.columns)
            if let error = model.form?.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { model.form = nil }
                    .keyboardShortcut(.cancelAction)
                Button("存储") { model.saveForm() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
