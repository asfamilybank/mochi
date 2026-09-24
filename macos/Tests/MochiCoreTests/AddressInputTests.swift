import Foundation
import Testing

@testable import MochiCore

@Suite struct AddressInputTests {
    @Test(arguments: [
        (input: "https://example.com/a?b=1", expected: "https://example.com/a?b=1"),
        (input: "http://example.com", expected: "http://example.com"),
        (input: "file:///tmp/x.html", expected: "file:///tmp/x.html"),
        (input: "about:blank", expected: "about:blank"),
        (input: "  https://example.com  ", expected: "https://example.com"),
        (input: "example.com", expected: "https://example.com"),
        (input: "example.com/path", expected: "https://example.com/path"),
        (input: "www.example.co.uk:8443/a?q=1", expected: "https://www.example.co.uk:8443/a?q=1"),
        (input: "localhost", expected: "https://localhost"),
        (input: "localhost:3000", expected: "https://localhost:3000"),
        (input: "localhost:3000/api", expected: "https://localhost:3000/api"),
        (input: "127.0.0.1:8080", expected: "https://127.0.0.1:8080"),
        (input: "192.168.1.1", expected: "https://192.168.1.1"),
        (input: "[::1]", expected: "https://[::1]"),
        (input: "[::1]:8080/x", expected: "https://[::1]:8080/x"),
    ])
    func treatsURLLikeInputAsAnAddress(_ row: (input: String, expected: String)) {
        #expect(AddressInput.resolve(row.input, searchEngine: .google)?.absoluteString == row.expected)
    }

    @Test(arguments: [
        (input: "foo bar", query: "foo%20bar"),
        (input: "hello", query: "hello"),
        (input: "咖啡", query: "%E5%92%96%E5%95%A1"),
        (input: "a&b=c", query: "a%26b%3Dc"),
        (input: "example.com is down", query: "example.com%20is%20down"),
        (input: "c++ #1?", query: "c%2B%2B%20%231%3F"),
        (input: "1.5", query: "1.5"),
        (input: ".com", query: ".com"),
    ])
    func searchesEverythingElse(_ row: (input: String, query: String)) {
        #expect(
            AddressInput.resolve(row.input, searchEngine: .google)?.absoluteString
                == "https://www.google.com/search?q=\(row.query)")
    }

    @Test(arguments: [
        (engine: SearchEngine.google, expected: "https://www.google.com/search?q=a%20%E4%B8%AD%26"),
        (engine: SearchEngine.bing, expected: "https://www.bing.com/search?q=a%20%E4%B8%AD%26"),
        (engine: SearchEngine.duckDuckGo, expected: "https://duckduckgo.com/?q=a%20%E4%B8%AD%26"),
        (engine: SearchEngine.baidu, expected: "https://www.baidu.com/s?wd=a%20%E4%B8%AD%26"),
    ])
    func eachEngineBuildsItsOwnQueryURL(_ row: (engine: SearchEngine, expected: String)) {
        #expect(AddressInput.resolve("a 中&", searchEngine: row.engine)?.absoluteString == row.expected)
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func blankInputDoesNotNavigate(_ input: String) {
        #expect(AddressInput.resolve(input, searchEngine: .google) == nil)
    }
}
