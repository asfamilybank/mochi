import Foundation
import Testing

@testable import MochiCore

@Suite struct WidgetConfigTests {
    @Test func parsesURLFromTOML() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.url == URL(string: "https://example.com"))
    }

    @Test func throwsWhenURLKeyMissing() {
        #expect(throws: WidgetConfigError.self) {
            try WidgetConfig.parse("")
        }
    }

    @Test func throwsWhenURLIsMalformed() {
        #expect(throws: WidgetConfigError.self) {
            try WidgetConfig.parse("url = \"\"")
        }
    }
}
