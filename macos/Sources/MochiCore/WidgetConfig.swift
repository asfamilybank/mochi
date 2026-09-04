import Foundation
import TOMLKit

public struct WidgetConfig: Equatable {
    /// An optional override of "resume last visited page" (#16's decision), edited via the
    /// settings panel's startup-URL tri-state selector (#13). `nil` means "not set" — kept
    /// distinct from the existing `url` field (which tracks *last visited*, updated by every
    /// toolbar navigation) so clearing this override can hand control back to `url` without
    /// losing browsing history. Resolving this into what actually loads on launch is #16's scope,
    /// not this type's.
    public enum StartupTarget: Equatable {
        case url(URL)
        case emptyPage
    }

    /// The last-visited URL — `nil` before the widget has ever loaded a real page (a fresh
    /// install with no `startup_target` override either, #16's "never configured/navigated
    /// anywhere" state). Updated by every toolbar navigation; resolving what actually loads on
    /// launch from this plus `startupTarget` is `resolveStartupContent`'s job, not this type's.
    public var url: URL?
    public var windowState: WindowState?
    public var customScript: String?
    public var ghostOpacity: Double
    public var snapThreshold: Double
    public var hotkeyMappings: [HotkeyMapping]
    public var startupTarget: StartupTarget?
    /// Built-in scripts (`BuiltInScripts.all`) the user has turned off via the settings panel
    /// (#15) — identified by `BuiltInScript.id` rather than storing an "enabled" flag per script,
    /// so a script added in a later app update defaults to enabled without needing a migration.
    public var disabledBuiltInScriptIDs: Set<String>

    public init(
        url: URL? = nil, windowState: WindowState? = nil, customScript: String? = nil,
        ghostOpacity: Double = WidgetConfig.defaultGhostOpacity, snapThreshold: Double = WindowSnapping.defaultThreshold,
        hotkeyMappings: [HotkeyMapping] = [], startupTarget: StartupTarget? = nil,
        disabledBuiltInScriptIDs: Set<String> = []
    ) {
        self.url = url
        self.windowState = windowState
        self.customScript = customScript
        self.ghostOpacity = ghostOpacity
        self.snapThreshold = snapThreshold
        self.hotkeyMappings = hotkeyMappings
        self.startupTarget = startupTarget
        self.disabledBuiltInScriptIDs = disabledBuiltInScriptIDs
    }
}

public enum WidgetConfigError: Error, Equatable {
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
        return WidgetConfig(
            url: try parseURL(from: table),
            windowState: parseWindowState(from: table["window"]?.table),
            customScript: table["custom_script"]?.string,
            ghostOpacity: table["ghost_opacity"]?.double ?? defaultGhostOpacity,
            snapThreshold: table["snap_threshold"]?.double ?? WindowSnapping.defaultThreshold,
            hotkeyMappings: parseHotkeyMappings(from: table["hotkey_mappings"]?.array),
            startupTarget: parseStartupTarget(from: table["startup_target"]?.table),
            disabledBuiltInScriptIDs: Set(table["disabled_built_in_scripts"]?.array?.compactMap(\.string) ?? [])
        )
    }

    /// `nil` when the `url` key is absent (#16: a fresh install with no browsing history yet is
    /// now a valid, expected state, not a config error) — but a *present* key that fails to parse
    /// as a URL still throws, since that's hand-edit corruption rather than "never visited".
    private static func parseURL(from table: TOMLTable) throws -> URL? {
        guard let urlString = table["url"]?.string else { return nil }
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw WidgetConfigError.invalidURL(urlString)
        }
        return url
    }

    /// A malformed table (unknown `kind`, or a `.url` case missing/mangling its URL) is treated
    /// the same as absent rather than thrown — this is hand-editable TOML like the rest of the
    /// file, and an invalid override should fall back to "not set" rather than crash the app on
    /// every launch (matching `parseHotkeyMappings`' own leniency for the same reason).
    private static func parseStartupTarget(from table: TOMLTable?) -> StartupTarget? {
        guard let table, let kind = table["kind"]?.string else { return nil }
        switch kind {
        case "url":
            guard let urlString = table["url"]?.string, let url = URL(string: urlString) else { return nil }
            return .url(url)
        case "empty_page":
            return .emptyPage
        default:
            return nil
        }
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
        if let url {
            table["url"] = url.absoluteString
        }
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
        if let startupTarget {
            let startupTable = TOMLTable()
            switch startupTarget {
            case .url(let url):
                startupTable["kind"] = "url"
                startupTable["url"] = url.absoluteString
            case .emptyPage:
                startupTable["kind"] = "empty_page"
            }
            table["startup_target"] = startupTable
        }
        if !disabledBuiltInScriptIDs.isEmpty {
            table["disabled_built_in_scripts"] = TOMLArray(disabledBuiltInScriptIDs.sorted())
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

    public func updatingGhostOpacity(_ ghostOpacity: Double) -> WidgetConfig {
        var copy = self
        copy.ghostOpacity = ghostOpacity
        return copy
    }

    public func updatingCustomScript(_ customScript: String?) -> WidgetConfig {
        var copy = self
        copy.customScript = customScript
        return copy
    }

    public func updatingStartupTarget(_ startupTarget: StartupTarget?) -> WidgetConfig {
        var copy = self
        copy.startupTarget = startupTarget
        return copy
    }

    public func updatingHotkeyMappings(_ hotkeyMappings: [HotkeyMapping]) -> WidgetConfig {
        var copy = self
        copy.hotkeyMappings = hotkeyMappings
        return copy
    }

    public func updatingDisabledBuiltInScriptIDs(_ disabledBuiltInScriptIDs: Set<String>) -> WidgetConfig {
        var copy = self
        copy.disabledBuiltInScriptIDs = disabledBuiltInScriptIDs
        return copy
    }
}
