import Foundation
import Testing

@testable import MochiCore

@Suite struct URLDisplayTests {
    /// #141: a page's address reads as Safari shows it, not as the escapes that carry it.
    @Test func decodesAChinesePath() throws {
        let url = try #require(URL(string: "https://zh.wikipedia.org/wiki/%E5%92%96%E5%95%A1"))
        #expect(URLDisplay.text(of: url) == "https://zh.wikipedia.org/wiki/咖啡")
    }

    /// Decoding these would change what the address says (a `/` that is not a path separator, a
    /// `?` that does not start a query) or hide part of it (a space), so they stay as Safari leaves them.
    @Test(arguments: [
        "https://example.com/a%20b",
        "https://example.com/a%2Fb",
        "https://example.com/a%3Fb=1",
        "https://example.com/100%25",
        "https://example.com/search?q=a%26b",
    ])
    func keepsASCIIEscapesEncoded(_ address: String) throws {
        let url = try #require(URL(string: address))
        #expect(URLDisplay.text(of: url) == address)
    }

    /// Bytes that are not UTF-8 have no character to show; the characters beside them still do.
    @Test(arguments: [
        (address: "https://example.com/%FF", shown: "https://example.com/%FF"),
        (address: "https://example.com/%E5%92", shown: "https://example.com/%E5%92"),
        (address: "https://example.com/%FF%E5%92%96", shown: "https://example.com/%FF咖"),
        (address: "https://example.com/%E5%92%96%E5%95", shown: "https://example.com/咖%E5%95"),
    ])
    func keepsBytesThatAreNotUTF8Encoded(_ example: (address: String, shown: String)) throws {
        let url = try #require(URL(string: example.address))
        #expect(URLDisplay.text(of: url) == example.shown)
    }

    /// A character that cannot be seen, or that turns the text after it around, would make the
    /// address read as something it is not: spaces (U+00A0, U+3000), a zero-width space
    /// (U+200B), a right-to-left override (U+202E) and a C1 control (U+0085).
    @Test(arguments: [
        "https://example.com/a%C2%A0b",
        "https://example.com/a%E3%80%80b",
        "https://example.com/a%E2%80%8Bb",
        "https://example.com/a%E2%80%AEb",
        "https://example.com/a%C2%85b",
    ])
    func keepsCharactersThatCannotBeSeenEncoded(_ address: String) throws {
        let url = try #require(URL(string: address))
        #expect(URLDisplay.text(of: url) == address)
    }

    /// Each character is judged on its own: one kept encoded doesn't keep its neighbour encoded.
    @Test func decodesAccentedLatinBesideAnInvisibleCharacter() throws {
        let url = try #require(URL(string: "https://example.com/caf%C3%A9%E2%80%8B"))
        #expect(URLDisplay.text(of: url) == "https://example.com/café%E2%80%8B")
    }
}
