import AppKit
import WebKit

/// Fetches the favicon for the page a `WKWebView` currently holds, for the address bar's leading
/// icon (`DesignTokens.AddressFieldLeadingIcon`).
///
/// WebKit exposes no favicon API on macOS — `WKWebView` knows the page's icon links no better than
/// any other DOM detail — so this reads the `<link rel="icon">` set out of the live document and
/// downloads the winner itself.
///
/// Every request goes to the site being visited, or to that origin's `/favicon.ico`. Public
/// favicon proxies (Google's `s2/favicons` and friends) are deliberately not used, however much
/// simpler they are: routing through one would hand a third party a request per site visited —
/// a browsing-history feed Mochi has no business creating, least of all for a decorative glyph.
final class FaviconLoader {
    /// Icons already fetched, keyed by origin. An origin's icon almost never changes within a
    /// session, and without this every in-site navigation would re-download the same bytes.
    /// Bounded because a long session wandering across many sites would otherwise accumulate
    /// decoded images with nothing ever evicting them.
    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []
    private static let cacheLimit = 64

    /// Origins whose icon could not be fetched, so a site with no favicon isn't re-probed on
    /// every single navigation within it. Same bound, same reasoning as `cache`.
    private var misses: Set<String> = []
    private var missOrder: [String] = []

    /// Ephemeral on purpose: a favicon needs no cookies, and not sending them keeps this request
    /// from being one more thing a site can tie to the session it already has with the page.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    /// Point size the icon is drawn at — matched to the SF Symbol it replaces, so swapping
    /// between `.siteIcon` and `.genericPage` doesn't change the field's leading metrics.
    static let iconPointSize: CGFloat = 16

    /// Largest favicon worth downloading. Some sites point `rel="icon"` at a full-size PNG logo;
    /// this is a 16pt glyph, so anything beyond this is bytes spent to be thrown away.
    private static let maxIconBytes = 512 * 1024

    /// Asks `webView` for its document's icon links, downloads the best one, and calls
    /// `completion` on the main queue — with `nil` when the page has no usable icon.
    ///
    /// The caller is responsible for discarding a result that arrived after navigating away:
    /// this is network-latency-bound, so a fast second navigation can easily outrun it.
    func loadIcon(for pageURL: URL, in webView: WKWebView, completion: @escaping (NSImage?) -> Void) {
        guard let origin = Self.origin(of: pageURL) else {
            completion(nil)
            return
        }
        if let cached = cache[origin] {
            completion(cached)
            return
        }
        if misses.contains(origin) {
            completion(nil)
            return
        }
        declaredIconURLs(in: webView) { [weak self] declared in
            guard let self else {
                completion(nil)
                return
            }
            // `/favicon.ico` is the fallback the web agreed on long before `rel="icon"` existed,
            // and plenty of sites still ship only that — so it's always tried last rather than
            // only when the document declares nothing.
            let candidates = declared + [URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL].compactMap { $0 }
            self.download(candidates, origin: origin, completion: completion)
        }
    }

    /// Walks `candidates` in order, stopping at the first that yields a decodable image.
    private func download(_ candidates: [URL], origin: String, completion: @escaping (NSImage?) -> Void) {
        var remaining = candidates
        guard !remaining.isEmpty else {
            remember(miss: origin)
            completion(nil)
            return
        }
        let next = remaining.removeFirst()
        session.dataTask(with: next) { [weak self] data, response, _ in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let statusOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            if statusOK, let data, !data.isEmpty, data.count <= Self.maxIconBytes,
                let image = Self.decode(data)
            {
                DispatchQueue.main.async {
                    self.remember(icon: image, for: origin)
                    completion(image)
                }
                return
            }
            self.download(remaining, origin: origin, completion: completion)
        }.resume()
    }

    /// Reads the document's declared icon links, best first. Runs in the page, so it sees the DOM
    /// as it actually is — including icons a single-page app injected after load.
    private func declaredIconURLs(in webView: WKWebView, completion: @escaping ([URL]) -> Void) {
        let javaScript = """
        (() => {
          const wanted = ["icon", "shortcut icon", "apple-touch-icon", "apple-touch-icon-precomposed"];
          const area = (link) => {
            const sizes = (link.getAttribute("sizes") || "").toLowerCase();
            if (sizes === "any") return Number.MAX_SAFE_INTEGER;
            const match = sizes.match(/(\\d+)x(\\d+)/);
            return match ? parseInt(match[1], 10) * parseInt(match[2], 10) : 0;
          };
          return [...document.querySelectorAll("link[rel][href]")]
            .filter((link) => wanted.includes((link.getAttribute("rel") || "").trim().toLowerCase()))
            .sort((a, b) => area(b) - area(a))
            .map((link) => link.href)
            .slice(0, 4);
        })()
        """
        webView.evaluateJavaScript(javaScript) { result, _ in
            let hrefs = (result as? [String]) ?? []
            // Only http(s): a `data:` icon would work but a `javascript:`/`file:` href is either
            // useless or something this has no business fetching.
            completion(hrefs.compactMap(URL.init(string:)).filter { ["http", "https"].contains($0.scheme) })
        }
    }

    /// `.ico` files carry several resolutions; `NSImage` keeps them all as separate
    /// representations and would otherwise hand AppKit whichever it feels like. This pins the
    /// drawn size so the leading icon can't come out blurry or oversized.
    private static func decode(_ data: Data) -> NSImage? {
        guard let source = NSImage(data: data), source.isValid, source.size.width > 0 else { return nil }
        let side = iconPointSize
        let scaled = NSImage(size: NSSize(width: side, height: side))
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero, operation: .sourceOver, fraction: 1)
        scaled.unlockFocus()
        scaled.accessibilityDescription = DesignTokens.AddressFieldLeadingIcon.siteIcon.accessibilityLabel
        return scaled
    }

    private func remember(icon: NSImage, for origin: String) {
        if cache[origin] == nil {
            cacheOrder.append(origin)
            if cacheOrder.count > Self.cacheLimit {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
        }
        cache[origin] = icon
    }

    private func remember(miss origin: String) {
        DispatchQueue.main.async {
            guard !self.misses.contains(origin) else { return }
            self.misses.insert(origin)
            self.missOrder.append(origin)
            if self.missOrder.count > Self.cacheLimit {
                self.misses.remove(self.missOrder.removeFirst())
            }
        }
    }

    /// Scheme + host + port — the granularity a favicon actually belongs to. Two pages on one
    /// site share an icon; `http` and `https` on the same host are different origins and may not.
    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
