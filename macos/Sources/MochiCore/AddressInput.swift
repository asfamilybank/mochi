import Foundation

/// The search engine the Smart Address Field hands non-address input to (#71). Stored in
/// `config.toml` as `search_engine = "<rawValue>"`; an unknown value falls back to `.google`.
public enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case bing
    case duckDuckGo = "duckduckgo"
    case baidu

    /// The name shown in the settings panel.
    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckDuckGo: return "DuckDuckGo"
        case .baidu: return "百度"
        }
    }

    /// Everything before the percent-encoded query.
    fileprivate var queryURLPrefix: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .duckDuckGo: return "https://duckduckgo.com/?q="
        case .baidu: return "https://www.baidu.com/s?wd="
        }
    }

    public func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: AddressInput.queryAllowed) else {
            return nil
        }
        return URL(string: queryURLPrefix + encoded)
    }
}

/// Decides what the Smart Address Field loads for a submitted text (#71) — pure, so the rules
/// are table-tested without AppKit.
public enum AddressInput {
    /// RFC 3986 unreserved characters only: everything else (space, `&`, `=`, `+`, `#`, CJK…) is
    /// percent-encoded, so the query survives as one parameter value.
    static let queryAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// - Blank input → `nil` (no navigation).
    /// - An explicit scheme (`https://…`, `about:blank`, `file:…`) → as-is. `host:port` is *not* a
    ///   scheme, so `localhost:3000` isn't misread as scheme `localhost`.
    /// - No whitespace and a host that is `localhost`, an IPv4 address, a bracketed IPv6 address
    ///   or a dotted hostname (optionally with port/path) → prefixed with `https://`.
    /// - Anything else → a search with `searchEngine`.
    public static func resolve(_ input: String, searchEngine: SearchEngine) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasWhitespace = trimmed.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
        if !hasWhitespace {
            if hasExplicitScheme(trimmed), let url = URL(string: trimmed) {
                return url
            }
            if looksLikeHost(trimmed), let url = URL(string: "https://\(trimmed)") {
                return url
            }
        }
        return searchEngine.searchURL(for: trimmed)
    }

    private static func hasExplicitScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.unicodeScalars.first, first.isASCII, CharacterSet.letters.contains(first),
            scheme.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+.-".unicodeScalars.contains($0)) })
        else { return false }
        // `name:1234`, `name:1234/…` is host:port, not a scheme.
        let rest = text[text.index(after: colon)...]
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty {
            let after = rest.dropFirst(digits.count)
            if after.isEmpty || "/?#".contains(after.first!) { return false }
        }
        return true
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        let authority = text.prefix { !"/?#".contains($0) }
        guard !authority.isEmpty, !authority.contains("@") else { return false }

        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return false }
            let address = authority[authority.index(after: authority.startIndex)..<close]
            guard isPort(authority[authority.index(after: close)...], allowEmpty: true) else { return false }
            var buffer = in6_addr()
            return inet_pton(AF_INET6, String(address), &buffer) == 1
        }

        var host = Substring(authority)
        if let colon = authority.lastIndex(of: ":") {
            guard isPort(authority[colon...], allowEmpty: false) else { return false }
            host = authority[..<colon]
        }
        if host.lowercased() == "localhost" { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 4, labels.allSatisfy({ UInt8($0) != nil }) { return true }
        guard labels.count >= 2, labels.allSatisfy({ isHostLabel($0) }) else { return false }
        // A numeric last label (`1.5`, `3.14`) is a number, not a domain.
        return !labels.last!.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `:1234` (or empty, when `allowEmpty`).
    private static func isPort(_ text: Substring, allowEmpty: Bool) -> Bool {
        if text.isEmpty { return allowEmpty }
        guard text.first == ":" else { return false }
        let digits = text.dropFirst()
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isHostLabel(_ label: Substring) -> Bool {
        !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-")
            && label.allSatisfy { $0 == "-" || $0.isLetter || $0.isNumber }
    }
}
