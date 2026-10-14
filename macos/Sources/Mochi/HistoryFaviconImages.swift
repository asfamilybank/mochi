import AppKit

/// The 历史记录 site icons (#117) decoded for drawing at 16pt, by `faviconID` — the window and
/// the menu each keep one. Each icon is decoded once: many visits show the same one, and rows and
/// menus are rebuilt often.
final class HistoryFaviconImages {
    private let png: (String) -> Data?
    private var images: [String: NSImage] = [:]

    /// - Parameter png: the store's bytes behind a `faviconID`.
    init(png: @escaping (String) -> Data?) {
        self.png = png
    }

    /// `nil` for a visit with no icon, or one the store no longer has.
    func image(for faviconID: String?) -> NSImage? {
        guard let faviconID else { return nil }
        if let image = images[faviconID] { return image }
        guard let data = png(faviconID), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        images[faviconID] = image
        return image
    }
}
