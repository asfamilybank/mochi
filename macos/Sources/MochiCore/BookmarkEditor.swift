import AppKit
import SwiftUI

/// The bookmark editor (#121, ADR-0033): a popover under the address bar that ⌘D opens on a page
/// it has just bookmarked (or that already was one — only then is 移除 offered). The bookmark
/// exists before this shows, so every way out keeps it unless 移除 is pressed: 完成, Return and a
/// click outside keep the name as typed; Esc keeps it as it was. The answer is given exactly once.
final class BookmarkEditorPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: BookmarkEditorModel
    private var answer: ((BookmarkEditorAnswer) -> Void)?

    init(name: String, offersRemove: Bool, answer: @escaping (BookmarkEditorAnswer) -> Void) {
        model = BookmarkEditorModel(name: name, offersRemove: offersRemove)
        self.answer = answer
        super.init()
        model.finish = { [weak self] in self?.finish($0) }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: BookmarkEditorView(model: model))
        popover.delegate = self
    }

    /// Shows the editor hanging from the bottom edge of `view`.
    func show(below view: NSView) {
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Closing for any reason other than a button or a key — a click outside, the window going
    /// away — keeps what was typed.
    func popoverDidClose(_ notification: Notification) {
        give(.done(name: model.name))
    }

    private func finish(_ result: BookmarkEditorAnswer) {
        give(result)
        popover.performClose(nil)
    }

    private func give(_ result: BookmarkEditorAnswer) {
        answer?(result)
        answer = nil
    }
}

private final class BookmarkEditorModel: ObservableObject {
    @Published var name: String
    let offersRemove: Bool
    var finish: (BookmarkEditorAnswer) -> Void = { _ in }

    init(name: String, offersRemove: Bool) {
        self.name = name
        self.offersRemove = offersRemove
    }
}

private struct BookmarkEditorView: View {
    @ObservedObject var model: BookmarkEditorModel
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("书签")
                .font(.headline)
            TextField("名称", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .focused($isNameFocused)
                .onSubmit { model.finish(.done(name: model.name)) }
            HStack {
                if model.offersRemove {
                    Button("移除") { model.finish(.remove) }
                }
                Spacer()
                Button("完成") { model.finish(.done(name: model.name)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onExitCommand { model.finish(.cancel) }
        .onAppear { isNameFocused = true }
    }
}
