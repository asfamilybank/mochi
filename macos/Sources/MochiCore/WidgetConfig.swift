import Foundation
import TOMLKit

public struct WidgetConfig: Equatable {
    public var url: URL
    public var windowState: WindowState?
    public var isPinned: Bool
    public var customScript: String?
    public var ghostOpacity: Double
    public var snapThreshold: Double
    public var hotkeyMappings: [HotkeyMapping]

    public init(
        url: URL, windowState: WindowState? = nil, isPinned: Bool = false, customScript: String? = nil,
        ghostOpacity: Double = WidgetConfig.defaultGhostOpacity, snapThreshold: Double = WindowSnapping.defaultThreshold,
        hotkeyMappings: [HotkeyMapping] = []
    ) {
        self.url = url
        self.windowState = windowState
        self.isPinned = isPinned
        self.customScript = customScript
        self.ghostOpacity = ghostOpacity
        self.snapThreshold = snapThreshold
        self.hotkeyMappings = hotkeyMappings
    }
}

public enum WidgetConfigError: Error, Equatable {
    case missingURL
    case invalidURL(String)
}

extension WidgetConfig {
    public static let defaultGhostOpacity: Double = 0.2

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
        return WidgetConfig(
            url: url,
            windowState: parseWindowState(from: table["window"]?.table),
            isPinned: table["pinned"]?.bool ?? false,
            customScript: table["custom_script"]?.string,
            ghostOpacity: table["ghost_opacity"]?.double ?? defaultGhostOpacity,
            snapThreshold: table["snap_threshold"]?.double ?? WindowSnapping.defaultThreshold,
            hotkeyMappings: parseHotkeyMappings(from: table["hotkey_mappings"]?.array)
        )
    }

    /// Hotkey Forwarding's (#11) user-configured mappings — until #14 ships a settings-panel
    /// editor for this table, hand-editing this array in the TOML file is the only way to set it
    /// (consistent with the domain doc's "power users can hand-edit the config" story). A
    /// malformed entry (out-of-range/negative numbers a hand-edit could easily introduce) is
    /// skipped rather than crashing the whole app on every launch — this is the boundary where
    /// untrusted external data enters the system, so it validates rather than trusting the file.
    private static func parseHotkeyMappings(from array: TOMLArray?) -> [HotkeyMapping] {
        guard let array else { return [] }
        return array.compactMap { value -> HotkeyMapping? in
            guard let table = value.table,
                let trigger = parseKeystroke(keyCodeKey: "trigger_key_code", modifiersKey: "trigger_modifiers", in: table),
                let pageKeystroke = parseKeystroke(keyCodeKey: "page_key_code", modifiersKey: "page_modifiers", in: table)
            else { return nil }
            return HotkeyMapping(trigger: trigger, pageKeystroke: pageKeystroke)
        }
    }

    /// `keyCode` must additionally fit `CGKeyCode` (`UInt16`) — the width `AppKitPlatformOps.
    /// forwardKeystroke` narrows it to when injecting via `CGEventPostToPid` — checked here
    /// instead, since this parsing boundary is where a bad hand-edited value should be rejected,
    /// not at the point of use.
    private static func parseKeystroke(keyCodeKey: String, modifiersKey: String, in table: TOMLTable) -> Hotkey? {
        guard let keyCodeInt = table[keyCodeKey]?.int,
            let modifiersInt = table[modifiersKey]?.int,
            let keyCode = UInt32(exactly: keyCodeInt), UInt16(exactly: keyCode) != nil,
            let modifierFlags = UInt32(exactly: modifiersInt)
        else { return nil }
        return Hotkey(keyCode: keyCode, modifierFlags: modifierFlags)
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
        table["pinned"] = isPinned
        table["ghost_opacity"] = ghostOpacity
        table["snap_threshold"] = snapThreshold
        if let customScript {
            table["custom_script"] = customScript
        }
        if let windowState {
            let windowTable = TOMLTable()
            windowTable["x"] = windowState.frame.x
            windowTable["y"] = windowState.frame.y
            windowTable["width"] = windowState.frame.width
            windowTable["height"] = windowState.frame.height
            windowTable["zoom"] = windowState.zoom
            table["window"] = windowTable
        }
        if !hotkeyMappings.isEmpty {
            table["hotkey_mappings"] = TOMLArray(
                hotkeyMappings.map { mapping -> TOMLTable in
                    let mappingTable = TOMLTable()
                    mappingTable["trigger_key_code"] = Int(mapping.trigger.keyCode)
                    mappingTable["trigger_modifiers"] = Int(mapping.trigger.modifierFlags)
                    mappingTable["page_key_code"] = Int(mapping.pageKeystroke.keyCode)
                    mappingTable["page_modifiers"] = Int(mapping.pageKeystroke.modifierFlags)
                    return mappingTable
                })
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

    public func updatingPinned(_ isPinned: Bool) -> WidgetConfig {
        var copy = self
        copy.isPinned = isPinned
        return copy
    }
}
