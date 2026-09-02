import Foundation
import TOMLKit

public struct WidgetConfig: Equatable {
    public var url: URL
    public var windowState: WindowState?

    public init(url: URL, windowState: WindowState? = nil) {
        self.url = url
        self.windowState = windowState
    }
}

public enum WidgetConfigError: Error, Equatable {
    case missingURL
    case invalidURL(String)
}

extension WidgetConfig {
    public static var defaultConfigURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mochi", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    public static func load(from fileURL: URL) throws -> WidgetConfig {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try parse(contents)
    }

    public static func parse(_ tomlString: String) throws -> WidgetConfig {
        let table = try TOMLTable(string: tomlString)
        guard let urlString = table["url"]?.string, !urlString.isEmpty else {
            throw WidgetConfigError.missingURL
        }
        guard let url = URL(string: urlString) else {
            throw WidgetConfigError.invalidURL(urlString)
        }
        return WidgetConfig(url: url, windowState: parseWindowState(from: table["window"]?.table))
    }

    private static func parseWindowState(from table: TOMLTable?) -> WindowState? {
        guard let table,
            let x = table["x"]?.double,
            let y = table["y"]?.double,
            let width = table["width"]?.double,
            let height = table["height"]?.double,
            let zoom = table["zoom"]?.double
        else { return nil }
        return WindowState(frame: WindowFrame(x: x, y: y, width: width, height: height), zoom: zoom)
    }

    public func serialized() -> String {
        let table = TOMLTable()
        table["url"] = url.absoluteString
        if let windowState {
            let windowTable = TOMLTable()
            windowTable["x"] = windowState.frame.x
            windowTable["y"] = windowState.frame.y
            windowTable["width"] = windowState.frame.width
            windowTable["height"] = windowState.frame.height
            windowTable["zoom"] = windowState.zoom
            table["window"] = windowTable
        }
        return table.convert()
    }

    public func write(to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try serialized().write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func updatingWindowState(_ windowState: WindowState) -> WidgetConfig {
        var copy = self
        copy.windowState = windowState
        return copy
    }

    public func updatingURL(_ url: URL) -> WidgetConfig {
        var copy = self
        copy.url = url
        return copy
    }
}
