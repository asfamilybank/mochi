import Foundation

/// One row of the Empty Page's hotkey quick reference (#83): the action on the left, one keycap
/// per key on the right.
public struct HotkeyQuickReferenceEntry: Equatable, Sendable {
    public var label: String
    public var keys: [String]

    public init(label: String, keys: [String]) {
        self.label = label
        self.keys = keys
    }
}

public enum HotkeyQuickReference {
    /// The hotkeys in effect under `config` — rebound ones as rebound, cleared ones left out — so
    /// pressing what the page shows always does something. Everything but toggling Ghost Mode
    /// and opening Settings only acts in Ghost Mode, and the Empty Page is Normal Mode content
    /// (ADR-0012), so those rows say so; otherwise pressing one here would read as broken.
    public static func entries(for config: WidgetConfig) -> [HotkeyQuickReferenceEntry] {
        var entries: [HotkeyQuickReferenceEntry] = []
        for action in HotkeyAction.allCases {
            guard let hotkey = config.hotkey(for: action) else { continue }
            entries.append(HotkeyQuickReferenceEntry(label: label(for: action), keys: HotkeyDisplay.keys(of: hotkey)))
        }
        for action in VideoControlAction.allCases {
            guard let trigger = config.videoControlTrigger(for: action) else { continue }
            entries.append(HotkeyQuickReferenceEntry(label: "\(label(for: action, seekStep: config.videoSeekStep))（幽灵模式下）", keys: HotkeyDisplay.keys(of: trigger)))
        }
        entries.append(HotkeyQuickReferenceEntry(label: "打开设置", keys: HotkeyDisplay.keys(of: DefaultHotkeys.openSettings)))
        return entries
    }

    private static func label(for action: HotkeyAction) -> String {
        switch action {
        case .toggleGhostMode: action.displayName
        case .hideWidget: "\(action.displayName)（幽灵模式下）"
        }
    }

    private static func label(for action: VideoControlAction, seekStep: Int) -> String {
        switch action {
        case .togglePlayback: action.displayName
        case .seekBackward, .seekForward: "\(action.displayName) \(seekStep) 秒"
        }
    }
}
