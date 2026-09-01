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

    @Test func windowStateIsNilWhenAbsent() throws {
        let config = try WidgetConfig.parse("url = \"https://example.com\"")
        #expect(config.windowState == nil)
    }

    @Test func parsesWindowStateWhenPresent() throws {
        let toml = """
        url = "https://example.com"

        [window]
        x = 10.0
        y = 20.0
        width = 800.0
        height = 600.0
        zoom = 1.25
        """

        let config = try WidgetConfig.parse(toml)

        #expect(
            config.windowState
                == WindowState(frame: WindowFrame(x: 10, y: 20, width: 800, height: 600), zoom: 1.25))
    }

    @Test func serializingThenReparsingRoundTripsWindowState() throws {
        let original = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 1, y: 2, width: 3, height: 4), zoom: 1.5)
        )

        let reparsed = try WidgetConfig.parse(original.serialized())

        #expect(reparsed == original)
    }

    @Test func writingThenLoadingFromDiskRoundTrips() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = WidgetConfig(
            url: URL(string: "https://example.com")!,
            windowState: WindowState(frame: WindowFrame(x: 1, y: 2, width: 3, height: 4), zoom: 1.5)
        )

        try original.write(to: fileURL)
        let loaded = try WidgetConfig.load(from: fileURL)

        #expect(loaded == original)
    }

    @Test func updatingWindowStateReturnsCopyWithNewStateOnly() {
        let config = WidgetConfig(url: URL(string: "https://example.com")!)
        let newState = WindowState(frame: WindowFrame(x: 0, y: 0, width: 100, height: 100), zoom: 2.0)

        let updated = config.updatingWindowState(newState)

        #expect(updated.windowState == newState)
        #expect(updated.url == config.url)
    }
}
