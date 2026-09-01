import Foundation
import TOMLKit

public struct WidgetConfig {
    public let url: URL

    public init(url: URL) {
        self.url = url
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
        return WidgetConfig(url: url)
    }
}
