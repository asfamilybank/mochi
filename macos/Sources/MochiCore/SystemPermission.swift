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
        /// The top of the 幽灵模式 panel, above everything that needs the permission (#103).
        case ghostModePanelTop
        /// An entry in the tray menu, the one place that reaches the user in Ghost Mode (#103).
        case trayMenu
        /// Top of 网站 → 摄像头 / 麦克风 (#104): the page of the prompt's own `permission`.
        case websitesPermissionPage
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
    /// Accessibility (#103): whenever it is not granted and `VideoControl` has something to listen
    /// for, at the top of the 幽灵模式 panel and in the tray. The system answers nothing finer than
    /// "trusted or not" for it, so the button is always 打开系统设置.
    public static func prompts(
        for config: WidgetConfig, status: (SystemPermission) -> SystemPermissionStatus
    ) -> [SystemPermissionPrompt] {
        var prompts: [SystemPermissionPrompt] = []
        if VideoControl.needsAccessibility(for: config), status(.accessibility) != .authorized {
            prompts += [SystemPermissionPrompt.Placement.ghostModePanelTop, .trayMenu].map {
                SystemPermissionPrompt(permission: .accessibility, placement: $0, action: .openSystemSettings)
            }
        }
        // #104: camera and microphone, each at the top of its own 网站 page and judged apart, while
        // the 网页权限 lets pages through and the system has not granted Mochi the device —
        // 请求权限 while the system has never asked, 打开系统设置 once it has refused, and no
        // button when a management policy decides.
        for device in [SystemPermission.camera, .microphone] where pagesMayUse(device, config: config) {
            let action: SystemPermissionPrompt.Action?
            switch status(device) {
            case .notDetermined: action = .request
            case .denied: action = .openSystemSettings
            case .restricted: action = nil
            case .authorized, .unqueryable: continue
            }
            prompts.append(SystemPermissionPrompt(permission: device, placement: .websitesPermissionPage, action: action))
        }
        return prompts
    }

    /// Whether a page can get as far as the system's gate for `device`: a page needs the 网页权限
    /// first, then the 系统权限 (CONTEXT.md), so while the 网页权限 is 拒绝 the system's answer is
    /// beside the point and no prompt shows. The one place this is decided — once websites can
    /// have exceptions, it widens to "the default or any exception is not 拒绝".
    private static func pagesMayUse(_ device: SystemPermission, config: WidgetConfig) -> Bool {
        switch device {
        case .camera: config.cameraPermission != .deny
        case .microphone: config.microphonePermission != .deny
        case .accessibility, .downloadsFolder: false
        }
    }
}
