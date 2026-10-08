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
    /// Ghost Mode's mouse-entered avoidance (ADR-0012), on by default. Edited from the settings
    /// panel's 窗口与外观 tab (#46); read at the moment of each visibility decision, never cached.
    public var isMouseAvoidanceEnabled: Bool
    /// Magnetic edge/corner snapping while dragging (#6), on by default. Edited from the same
    /// 窗口与外观 tab and re-applied to the live window on every change (#46).
    public var isSnapEnabled: Bool
    public var hotkeyMappings: [HotkeyMapping]
    public var startupTarget: StartupTarget?
    /// Built-in scripts (`BuiltInScripts.all`) the user has turned off via the settings panel
    /// (#15) — identified by `BuiltInScript.id` rather than storing an "enabled" flag per script,
    /// so a script added in a later app update defaults to enabled without needing a migration.
    public var disabledBuiltInScriptIDs: Set<String>
    /// The user's *explicit* rebindings of Mochi's two global hotkeys (#45), keyed by action —
    /// same shape as `disabledBuiltInScriptIDs`: only what the user changed is stored, an absent
    /// key means "use `HotkeyAction.defaultHotkey`". So a later change to a default needs no
    /// migration and the file never fills up with entries that just restate the defaults. Read
    /// through `hotkey(for:)`, never directly.
    public var hotkeyOverrides: [HotkeyAction: Hotkey]
    /// #73: inline CSS injected on every navigation (see `CustomStylesheet`); `nil` = none,
    /// and then omitted from `config.toml`. Not an init parameter — set via
    /// `updatingCustomStylesheet`, so the long memberwise init stays untouched.
    public var customStylesheet: String? = nil

    /// 网页内容 → 自动播放 (#70), Safari's three options mapped onto WebKit's
    /// `mediaTypesRequiringUserActionForPlayback`. Read once, when the web view is created — the
    /// public API has no per-navigation equivalent — so an edit applies on the next open.
    public enum AutoplayPolicy: String, CaseIterable, Equatable, Sendable {
        case allowAll = "allow_all"
        case stopMediaWithSound = "stop_media_with_sound"
        case never = "never"
    }

    /// Defaults to `.allowAll`: a widget reopened on a video page should just keep playing.
    public var autoplayPolicy: AutoplayPolicy = .allowAll

    /// 高级 → 字体大小不得小于 (#70). `nil` = no limit (the checkbox unticked); otherwise one of
    /// `offeredMinimumFontSizes`. Pushed to the live web view by `Orchestrator.reapplyConfiguration`.
    public var minimumFontSize: Int?

    /// 高级 → 安全性 → 通过 HTTP 连接网站前接收警告 (#72), off by default. Consulted by the
    /// platform in every navigation policy decision.
    public var isHTTPWarningEnabled: Bool = false
    /// 高级 → 显示网页开发者功能 (#72), off by default — `WKWebView.isInspectable`.
    public var isWebInspectorEnabled: Bool = false

    /// 网页内容 → 摄像头 / 麦克风 (#69), Safari's three options. Read at each request, so an edit
    /// applies from the next request on; the decision itself is `MediaCaptureDecision.deciding`.
    public enum MediaCapturePermission: String, CaseIterable, Equatable, Sendable {
        case ask
        case deny
        case allow
    }

    /// Both default to `.ask`, handing the request to WebKit's own prompt.
    public var cameraPermission: MediaCapturePermission = .ask
    public var microphonePermission: MediaCapturePermission = .ask
    /// 网页内容 → 弹出式窗口 (#67), Safari's wording. Maps to WebKit's
    /// `javaScriptCanOpenWindowsAutomatically`: 阻止 lets WebKit drop a `window.open` that no user
    /// click started, 允许 lets it through to the new-window decision (ADR-0017).
    public enum PopupWindowPolicy: String, CaseIterable, Equatable, Sendable {
        case allow
        case block
    }

    /// Defaults to `.block`, like Safari. Pushed to the live web view by
    /// `Orchestrator.reapplyConfiguration`.
    public var popupWindowPolicy: PopupWindowPolicy = .block

    /// Where the Smart Address Field sends non-address input (#71), Google by default. Edited
    /// from the 通用 pane and read at the moment of each submit, never cached.
    public var searchEngine: SearchEngine

    /// 通用 → 文件下载位置 (#68), 下载 by default. Read at the moment of each download, never cached.
    public var downloadLocation: DownloadLocation = .downloadsFolder

    public init(
        url: URL? = nil, windowState: WindowState? = nil, customScript: String? = nil,
        ghostOpacity: Double = WidgetConfig.defaultGhostOpacity, isMouseAvoidanceEnabled: Bool = true,
        isSnapEnabled: Bool = true,
        hotkeyMappings: [HotkeyMapping] = [], startupTarget: StartupTarget? = nil,
        disabledBuiltInScriptIDs: Set<String> = [],
        hotkeyOverrides: [HotkeyAction: Hotkey] = [:],
        searchEngine: SearchEngine = .google
    ) {
        self.url = url
        self.windowState = windowState
        self.customScript = customScript
        self.ghostOpacity = ghostOpacity
        self.isMouseAvoidanceEnabled = isMouseAvoidanceEnabled
        self.isSnapEnabled = isSnapEnabled
        self.hotkeyMappings = hotkeyMappings
        self.startupTarget = startupTarget
        self.disabledBuiltInScriptIDs = disabledBuiltInScriptIDs
        self.hotkeyOverrides = hotkeyOverrides
        self.searchEngine = searchEngine
    }

    /// The combo currently in effect for `action`: the user's override if there is one, else the
    /// built-in default.
    public func hotkey(for action: HotkeyAction) -> Hotkey {
        hotkeyOverrides[action] ?? action.defaultHotkey
    }
}

public enum WidgetConfigError: Error, Equatable {
    case invalidURL(String)
}

extension WidgetConfig {
    public static let defaultGhostOpacity: Double = 0.2

    /// The sizes the 字体大小不得小于 popup offers (Safari's list, #70). A hand-edited value outside
    /// it falls back to "no limit" rather than being honoured, so the popup can always show it.
    public static let offeredMinimumFontSizes: [Int] = [9, 10, 11, 12, 14, 18, 24]

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
        var config = WidgetConfig(
            url: try parseURL(from: table),
            windowState: parseWindowState(from: table["window"]?.table),
            customScript: table["custom_script"]?.string,
            ghostOpacity: table["ghost_opacity"]?.double ?? defaultGhostOpacity,
            isMouseAvoidanceEnabled: table["mouse_avoidance_enabled"]?.bool ?? true,
            isSnapEnabled: table["snap_enabled"]?.bool ?? true,
            hotkeyMappings: parseHotkeyMappings(from: table["hotkey_mappings"]?.array),
            startupTarget: parseStartupTarget(from: table["startup_target"]?.table),
            disabledBuiltInScriptIDs: Set(table["disabled_built_in_scripts"]?.array?.compactMap(\.string) ?? []),
            hotkeyOverrides: parseHotkeyOverrides(from: table["hotkeys"]?.table),
            searchEngine: table["search_engine"]?.string.flatMap(SearchEngine.init(rawValue:)) ?? .google
        )
        config.customStylesheet = table["custom_stylesheet"]?.string
        // #70 — invalid values fall back to the defaults, like the rest of this hand-editable file.
        config.autoplayPolicy = table["autoplay"]?.string.flatMap(AutoplayPolicy.init(rawValue:)) ?? .allowAll
        config.minimumFontSize = table["minimum_font_size"]?.int.flatMap {
            offeredMinimumFontSizes.contains($0) ? $0 : nil
        }
        // #67
        config.popupWindowPolicy = table["popup_windows"]?.string.flatMap(PopupWindowPolicy.init(rawValue:)) ?? .block
        // #72
        config.isHTTPWarningEnabled = table["http_warning_enabled"]?.bool ?? false
        config.isWebInspectorEnabled = table["web_inspector_enabled"]?.bool ?? false
        config.downloadLocation = parseDownloadLocation(from: table)
        // #69 — anything but the three exact values falls back to 询问.
        config.cameraPermission = table["camera_permission"]?.string.flatMap(MediaCapturePermission.init(rawValue:)) ?? .ask
        config.microphonePermission =
            table["microphone_permission"]?.string.flatMap(MediaCapturePermission.init(rawValue:)) ?? .ask
        return config
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

    /// `[hotkeys]` (#45): one sub-table per overridden action, keyed by `HotkeyAction.rawValue`.
    /// Same leniency as `parseHotkeyMappings`: an unknown action identifier (a typo, or an action
    /// a later version removed) is ignored, and a malformed entry falls back to that action's
    /// default rather than throwing — an override that can't be parsed must never brick the app.
    private static func parseHotkeyOverrides(from table: TOMLTable?) -> [HotkeyAction: Hotkey] {
        guard let table else { return [:] }
        var overrides: [HotkeyAction: Hotkey] = [:]
        for action in HotkeyAction.allCases {
            guard let entry = table[action.rawValue]?.table,
                let hotkey = parseKeystroke(keyCodeKey: "key_code", modifiersKey: "modifiers", in: entry)
            else { continue }
            overrides[action] = hotkey
        }
        return overrides
    }

    /// #68: `download_location = "downloads" | "ask" | "folder"`, the last with an absolute
    /// `download_folder` path (`~` expanded, for hand edits). Anything else — an unknown kind, a
    /// `folder` without a usable path — falls back to 下载 rather than failing the launch.
    private static func parseDownloadLocation(from table: TOMLTable) -> DownloadLocation {
        switch table["download_location"]?.string {
        case "ask":
            return .askEachTime
        case "folder":
            guard let raw = table["download_folder"]?.string else { return .downloadsFolder }
            let path = (raw as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { return .downloadsFolder }
            return .folder(URL(fileURLWithPath: path, isDirectory: true))
        default:
            return .downloadsFolder
        }
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
        table["mouse_avoidance_enabled"] = isMouseAvoidanceEnabled
        table["snap_enabled"] = isSnapEnabled
        table["http_warning_enabled"] = isHTTPWarningEnabled
        table["web_inspector_enabled"] = isWebInspectorEnabled
        table["search_engine"] = searchEngine.rawValue
        if let customScript {
            table["custom_script"] = customScript
        }
        if let customStylesheet {
            table["custom_stylesheet"] = customStylesheet
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
        if !hotkeyOverrides.isEmpty {
            let hotkeysTable = TOMLTable()
            for (action, hotkey) in hotkeyOverrides.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let entry = TOMLTable()
                entry["key_code"] = Int(hotkey.keyCode)
                entry["modifiers"] = Int(hotkey.modifierFlags)
                hotkeysTable[action.rawValue] = entry
            }
            table["hotkeys"] = hotkeysTable
        }
        // #70
        table["autoplay"] = autoplayPolicy.rawValue
        if let minimumFontSize {
            table["minimum_font_size"] = minimumFontSize
        }
        // #68 — the default (下载) is not written.
        switch downloadLocation {
        case .downloadsFolder:
            break
        case .askEachTime:
            table["download_location"] = "ask"
        case .folder(let folder):
            table["download_location"] = "folder"
            table["download_folder"] = folder.path
        }
        // #69
        table["camera_permission"] = cameraPermission.rawValue
        table["microphone_permission"] = microphonePermission.rawValue
        // #67 — only a departure from the default is written.
        if popupWindowPolicy != .block {
            table["popup_windows"] = popupWindowPolicy.rawValue
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

    public func updatingCustomStylesheet(_ customStylesheet: String?) -> WidgetConfig {
        var copy = self
        copy.customStylesheet = customStylesheet
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

    public func updatingMouseAvoidanceEnabled(_ enabled: Bool) -> WidgetConfig {
        var copy = self
        copy.isMouseAvoidanceEnabled = enabled
        return copy
    }

    public func updatingSnapEnabled(_ enabled: Bool) -> WidgetConfig {
        var copy = self
        copy.isSnapEnabled = enabled
        return copy
    }

    public func updatingAutoplayPolicy(_ policy: AutoplayPolicy) -> WidgetConfig {
        var copy = self
        copy.autoplayPolicy = policy
        return copy
    }

    public func updatingMinimumFontSize(_ size: Int?) -> WidgetConfig {
        var copy = self
        copy.minimumFontSize = size
        return copy
    }

    public func updatingPopupWindowPolicy(_ policy: PopupWindowPolicy) -> WidgetConfig {
        var copy = self
        copy.popupWindowPolicy = policy
        return copy
    }

    public func updatingHTTPWarningEnabled(_ enabled: Bool) -> WidgetConfig {
        var copy = self
        copy.isHTTPWarningEnabled = enabled
        return copy
    }

    public func updatingWebInspectorEnabled(_ enabled: Bool) -> WidgetConfig {
        var copy = self
        copy.isWebInspectorEnabled = enabled
        return copy
    }

    // #69
    public func updatingCameraPermission(_ permission: MediaCapturePermission) -> WidgetConfig {
        var copy = self
        copy.cameraPermission = permission
        return copy
    }

    public func updatingMicrophonePermission(_ permission: MediaCapturePermission) -> WidgetConfig {
        var copy = self
        copy.microphonePermission = permission
        return copy
    }

    public func updatingSearchEngine(_ searchEngine: SearchEngine) -> WidgetConfig {
        var copy = self
        copy.searchEngine = searchEngine
        return copy
    }

    public func updatingDownloadLocation(_ location: DownloadLocation) -> WidgetConfig {
        var copy = self
        copy.downloadLocation = location
        return copy
    }

    /// Rebinding an action back to its own default drops the entry instead of storing it — the
    /// override table records only what differs from the defaults (see `hotkeyOverrides`).
    public func updatingHotkeyOverride(_ action: HotkeyAction, to hotkey: Hotkey) -> WidgetConfig {
        var copy = self
        if hotkey == action.defaultHotkey {
            copy.hotkeyOverrides.removeValue(forKey: action)
        } else {
            copy.hotkeyOverrides[action] = hotkey
        }
        return copy
    }
}
