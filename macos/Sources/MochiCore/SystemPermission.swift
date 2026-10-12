import Foundation

/// A macOS permission granted to Mochi itself (CONTEXT.md「系统权限」, ADR-0026). The system keeps
/// it, per app identity: Mochi can only read where it stands, ask for it when it is needed, and
/// send the user to System Settings — all through `PlatformOps`.
public enum SystemPermission: CaseIterable, Hashable, Sendable {
    /// What lets 视频控制, and Hotkey Forwarding mappings set off by a tap or double tap, hear keys
    /// pressed in other apps.
    case accessibility
    case camera
    case microphone
    /// Where downloads land by default. A 文件和文件夹 permission: the system offers no query, so
    /// its status is always `.unqueryable`, and where it stands can only be inferred from the most
    /// recent write (`SystemPermissionMarker.downloadsFolderWriteDenied`).
    case downloadsFolder
}

/// Where a `SystemPermission` stands, as the system reports it.
public enum SystemPermissionStatus: Equatable, Sendable {
    /// 未询问: the system has never asked — a request brings up its dialog.
    case notDetermined
    /// 已拒绝: asked and refused. The system asks only once, so only System Settings can change it.
    /// Accessibility, for which the system answers no more than "trusted or not", reads as this
    /// whenever it is not granted.
    case denied
    /// 已授权.
    case authorized
    /// 受限制: a management policy decides it; neither Mochi nor the user can.
    case restricted
    /// 无法查询: the Downloads folder's only status (see `SystemPermission.downloadsFolder`).
    case unqueryable
}

/// Flags about 系统权限 kept across launches — in `UserDefaults`, never in `config.toml` or under
/// Application Support/Mochi, so deleting Mochi's data resets them no more than it resets the
/// system's own record of the permission (ADR-0026). The raw value is the defaults key.
public enum SystemPermissionMarker: String, CaseIterable, Hashable, Sendable {
    /// 视频控制 has asked for Accessibility on its own, the one time it ever may.
    case accessibilityAutoRequested = "systemPermissionAccessibilityAutoRequested"
    /// The most recent write into the Downloads folder failed for want of permission; the next
    /// one to succeed clears it.
    case downloadsFolderWriteDenied = "systemPermissionDownloadsFolderWriteDenied"
}

/// One explanation the settings panel shows because a `SystemPermission` is missing (ADR-0026).
/// A permission already granted never has one.
public struct SystemPermissionPrompt: Equatable, Sendable {
    /// Where in the settings panel it goes.
    public enum Placement: Equatable, Sendable {
        /// Below 视频控制's keys — where #79 put the Accessibility note.
        case videoControlSection
    }

    /// What its button does.
    public enum Action: Equatable, Sendable {
        /// 请求权限 — the system has never asked, so it still can.
        case request
        /// 打开系统设置 — straight to the permission's page in 隐私与安全性.
        case openSystemSettings
    }

    public var permission: SystemPermission
    public var placement: Placement
    /// `nil` when there is nothing to press: a restricted permission is not the user's to change.
    public var action: Action?

    public init(permission: SystemPermission, placement: Placement, action: Action?) {
        self.permission = permission
        self.placement = placement
        self.action = action
    }
}

public enum SystemPermissionPrompts {
    /// The prompts that belong on screen right now, given `config` and what `status` reports for
    /// each permission — read by the caller at the moment of asking, since System Settings changes
    /// them behind Mochi's back.
    ///
    /// For now this carries over #79's one rule: Accessibility, below 视频控制, whenever it is not
    /// granted. The system answers nothing finer than "trusted or not" for it, so the button is
    /// always 打开系统设置.
    public static func prompts(
        for config: WidgetConfig, status: (SystemPermission) -> SystemPermissionStatus
    ) -> [SystemPermissionPrompt] {
        var prompts: [SystemPermissionPrompt] = []
        if status(.accessibility) != .authorized {
            prompts.append(SystemPermissionPrompt(
                permission: .accessibility, placement: .videoControlSection, action: .openSystemSettings))
        }
        return prompts
    }
}
