import Foundation

/// A trigger key (CONTEXT.md, ADR-0022): what is pressed to set off a 视频控制 action (#74) or,
/// since #92, a Hotkey Forwarding mapping — a side-specific modifier tapped on its own, the
/// video keys' default because tapping a modifier types nothing and moves no cursor in any app;
/// the same modifier tapped twice (#91); or a combo.
public enum TriggerKey: Hashable, Sendable {
    case modifierTap(ModifierKey)
    /// The same modifier tapped twice in quick succession (#91, ADR-0022).
    case modifierDoubleTap(ModifierKey)
    case keystroke(Hotkey)

    /// Which of the three kinds of trigger key this is (#90) — what the settings row's
    /// dropdown shows.
    public var kind: TriggerKind {
        switch self {
        case .modifierTap: .tap
        case .modifierDoubleTap: .doubleTap
        case .keystroke: .combo
        }
    }
}

/// How a trigger key is pressed (CONTEXT.md, ADR-0022): a modifier tapped on its own, the same
/// modifier tapped twice, or a combo. The settings rows that can take more than one let the user
/// pick first (#90).
public enum TriggerKind: CaseIterable, Hashable, Sendable {
    case tap
    case doubleTap
    case combo

    public var displayName: String {
        switch self {
        case .tap: "轻按"
        case .doubleTap: "连按两次"
        case .combo: "组合键"
        }
    }
}
