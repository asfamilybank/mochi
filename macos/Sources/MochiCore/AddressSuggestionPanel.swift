import AppKit

/// The list under the address bar while the user types (#122, ADR-0034) — drawn from
/// `AddressEditingSession`'s rows and nothing else. A child window of the widget, so it follows
/// the widget and may reach past its edges when the widget is small: left-aligned with the address
/// bar and at least `minimumWidth` wide.
///
/// It never becomes key: the address bar keeps the keyboard, and a click on a row reaches the row
/// without first activating the list.
final class AddressSuggestionPanel {
    static let minimumWidth: CGFloat = 400
    static let rowHeight: CGFloat = 28
    private static let inset: CGFloat = 5

    private let panel: NSPanel
    private let stack = NSStackView()
    /// The bookmarks listed before typing (#125) may be many: past `visibleRows` the list scrolls.
    private let scrollView = NSScrollView()
    private static let visibleRows = AddressEditingSession.maximumRows
    /// A click on row `index`.
    var onChoose: ((Int) -> Void)?
    /// The PNG behind a page row's `faviconID`.
    var favicon: (String) -> Data? = { _ in nil }

    init() {
        panel = SuggestionWindow(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        panel.contentView = background

        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scrollView.documentView = document
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.inset),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.inset),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.inset),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.inset),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
        ])
        panel.setAccessibilityRole(.list)
        panel.setAccessibilityLabel("地址栏建议")
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows `rows` hanging from `anchor` (the address bar), `selected` highlighted.
    func show(rows: [AddressSuggestionRow], selected: Int?, below anchor: NSView) {
        guard let parent = anchor.window else { return }
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, row) in rows.enumerated() {
            let view = SuggestionRowView(row: row, icon: icon(for: row), isSelected: index == selected)
            view.onClick = { [weak self] in self?.onChoose?(index) }
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let anchorRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let width = max(anchorRect.width, Self.minimumWidth)
        let height = CGFloat(min(rows.count, Self.visibleRows)) * Self.rowHeight + 2 * Self.inset
        panel.setFrame(
            NSRect(x: anchorRect.minX, y: anchorRect.minY - 6 - height, width: width, height: height), display: true)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        if let selected, stack.arrangedSubviews.indices.contains(selected) {
            stack.layoutSubtreeIfNeeded()
            stack.arrangedSubviews[selected].scrollToVisible(stack.arrangedSubviews[selected].bounds)
        } else {
            scrollView.contentView.scroll(to: .zero)
        }
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func icon(for row: AddressSuggestionRow) -> NSImage? {
        switch row {
        case .open:
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        case .search:
            return NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        case .page(let page):
            if let id = page.faviconID, let data = favicon(id), let image = NSImage(data: data) {
                image.size = NSSize(width: 16, height: 16)
                return image
            }
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Never key, so the address bar keeps typing while the list is up.
private final class SuggestionWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One row: an icon, then the text — 「打开 …」, 「用 … 搜索 “…”」, or a page's title with its
/// address after it, dimmed.
private final class SuggestionRowView: NSView {
    var onClick: (() -> Void)?
    private let isSelected: Bool

    init(row: AddressSuggestionRow, icon: NSImage?, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: AddressSuggestionPanel.rowHeight).isActive = true

        let iconView = NSImageView(image: icon ?? NSImage())
        iconView.contentTintColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithAttributedString: Self.text(for: row, isSelected: isSelected))
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(iconView)
        addSubview(label)
        // #125: a bookmark is marked at the row's end.
        let mark = NSImageView(image: NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil) ?? NSImage())
        mark.contentTintColor = iconView.contentTintColor
        mark.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.isHidden = !Self.isBookmark(row)
        addSubview(mark)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: mark.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.isBookmark(row) ? "书签：\(label.stringValue)" : label.stringValue)
        setAccessibilitySelected(isSelected)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    /// #142: the row is one button whose label says it all — its icons are decoration (an
    /// unlabeled symbol reads as「地球仪键」) and its text field only repeats the label. Marking the
    /// subviews as non-elements does not hide an `NSImageView`, so the row lists none.
    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    private static func isBookmark(_ row: AddressSuggestionRow) -> Bool {
        if case .page(let page) = row { page.isBookmark } else { false }
    }

    private static func text(for row: AddressSuggestionRow, isSelected: Bool) -> NSAttributedString {
        let primary: NSColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        let secondary: NSColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = NSMutableAttributedString()
        func append(_ string: String, _ color: NSColor) {
            text.append(NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font]))
        }
        switch row {
        case .open(let url):
            append("打开 ", secondary)
            append(display(url), primary)
        case .search(let query, let engine):
            append("用 \(engine.displayName) 搜索 ", secondary)
            append("“\(query)”", primary)
        case .page(let page):
            let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            append(title.isEmpty ? display(page.url) : title, primary)
            if !title.isEmpty { append(" — \(display(page.url))", secondary) }
        }
        return text
    }

    /// The address as it reads best: decoded (#141), no `https://`, no trailing `/` on a bare host.
    private static func display(_ url: URL) -> String {
        var text = URLDisplay.text(of: url)
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if url.path == "/" || url.path.isEmpty, url.query == nil, text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
