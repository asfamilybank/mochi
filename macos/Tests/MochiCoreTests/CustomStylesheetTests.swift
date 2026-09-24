import Foundation
import Testing
@testable import MochiCore

/// #73: the stylesheet is embedded in a JS string literal — it must survive quotes,
/// backslashes, newlines and a literal `</style>` without breaking out of the string.
struct CustomStylesheetTests {
    @Test func embedsTheCSSAsAJSONStringLiteral() throws {
        let css = "a::after { content: \"\\\\\" '</style>'; }\n\tb { }\u{2028}"

        let source = CustomStylesheet.injectionSource(for: css)

        let literal = try #require(Self.embeddedLiteral(in: source))
        let decoded = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
        #expect(decoded == css)
        #expect(!literal.contains("\n"))
        #expect(!literal.contains("</"))
        #expect(!literal.contains("\u{2028}"))
    }

    @Test func createsAStyleElementReplacingAnyPreviousOne() {
        let source = CustomStylesheet.injectionSource(for: "b {}")
        #expect(source.contains("createElement('style')"))
        #expect(source.contains(CustomStylesheet.elementID))
    }

    /// The JSON literal sits between `.textContent = ` and the following `;` + newline.
    private static func embeddedLiteral(in source: String) -> String? {
        guard let start = source.range(of: ".textContent = ")?.upperBound,
              let end = source.range(of: ";\n", range: start..<source.endIndex)?.lowerBound
        else { return nil }
        return String(source[start..<end])
    }
}
