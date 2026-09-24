import Foundation

/// #73: the custom stylesheet, Script Injection's third source (CONTEXT.md). WebKit has no
/// public user-stylesheet API, so the CSS travels as a script that creates a `<style>` element.
/// It rides the same per-navigation `injectScript` path as the custom script, which runs after
/// the page's own styles are in place — appending the element last makes it win cascade ties.
public enum CustomStylesheet {
    /// Re-injecting (e.g. a same-document navigation) replaces the previous element instead of
    /// stacking copies.
    public static let elementID = "mochi-custom-stylesheet"

    /// The CSS is embedded as a JSON string literal (valid JS), so quotes, backslashes and
    /// newlines can't break out; `</` and U+2028/U+2029 are additionally escaped.
    public static func injectionSource(for css: String) -> String {
        let data = (try? JSONEncoder().encode(css)) ?? Data("\"\"".utf8)
        let literal = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return """
        (function () {
        var old = document.getElementById('\(elementID)');
        if (old) { old.remove(); }
        var style = document.createElement('style');
        style.id = '\(elementID)';
        style.textContent = \(literal);
        (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
}
