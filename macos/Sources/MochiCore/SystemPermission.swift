import Foundation

/// A macOS permission granted to Mochi itself (CONTEXT.md「系统权限」, ADR-0026). The system keeps
/// it, per app identity: Mochi can only read where it stands, ask for it when it is needed, and
/// send the user to System Settings — all through `PlatformOps`.
public enum SystemPermission: CaseIterable, Hashable, Sendable {
    /// 辅助功能: what lets 视频控制 hear, in other apps, a combo the system takes for typing — one
    /// with neither ⌃ nor ⌘ (ADR-0029). The system answers no more than "trusted or not" for it:
    /// the platform reads it as `.authorized` or `.denied`, and Mochi tells 未询问 from 已拒绝 by
    /// its own record (`SystemPermissionStatus.accessibility(isTrusted:requested:)`).
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
    case denied
    /// 已授权.
    case authorized
    /// 受限制: a management policy decides it; neither Mochi nor the user can.
    case restricted
    /// 无法查询: the Downloads folder's only status (see `SystemPermission.downloadsFolder`).
    case unqueryable
}

extension SystemPermissionStatus {
    /// Where Accessibility stands (#111, ADR-0029). The system says only whether Mochi is trusted,
    /// not whether it ever asked, so Mochi's own record of having asked
    /// (`SystemPermissionMarker.accessibilityRequested`) stands in: not trusted and never asked is
    /// 未询问 (请求权限), not trusted after asking is 已拒绝 (打开系统设置).
    public static func accessibility(isTrusted: Bool, requested: Bool) -> SystemPermissionStatus {
        if isTrusted { return .authorized }
        return requested ? .denied : .notDetermined
    }
}

/// Flags about 系统权限 kept across launches — in `UserDefaults`, never in `config.toml` or under
/// Application Support/Mochi, so deleting Mochi's data resets them no more than it resets the
/// system's own record of the permission (ADR-0026). The raw value is the defaults key.
public enum SystemPermissionMarker: String, CaseIterable, Hashable, Sendable {
    /// Mochi has asked for Accessibility (#103, #111): 视频控制 on its own, the one time it ever
    /// may, or the user from a 请求权限 button. It is also how 未询问 is told from 已拒绝, which
    /// the system doesn't say for Accessibility. The key is #103's, from when only the automatic
    /// request set it.
    case accessibilityRequested = "systemPermissionAccessibilityAutoRequested"
    /// The most recent write into the Downloads folder failed for want of permission; the next
    /// one to succeed clears it.
    case downloadsFolderWriteDenied = "systemPermissionDownloadsFolderWriteDenied"
}

/// One explanation the settings panel shows because a `SystemPermission` is missing (ADR-0026).
/// A permission already granted never has one.
public struct SystemPermissionPrompt: Equatable, Sendable {
    /// Where in the settings panel it goes.
    public enum Placement: Equatable, Sendable {
        /// The top of the 幽灵模式 panel, above everything that needs the permission (#103, #111).
        case ghostModePanelTop
        /// An entry in the tray menu, the one place that reaches the user in Ghost Mode (#103).
        case trayMenu
        /// Top of 网站 → 摄像头 / 麦克风 (#104): the page of the prompt's own `permission`.
        case websitesPermissionPage
        /// Beside 通用 → 文件下载位置 (#105).
        case downloadLocation
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

    /// Presses its button, wherever it shows — the settings panel or the tray. 请求权限 for
    /// Accessibility first notes that Mochi has asked (`SystemPermissionMarker.accessibilityRequested`):
    /// the system won't say so itself, and from then on the button is 打开系统设置 (#111).
    func perform(on platformOps: PlatformOps) {
        switch action {
        case .request:
            if permission == .accessibility { platformOps.setSystemPermissionMarker(.accessibilityRequested, true) }
            platformOps.requestSystemPermission(permission)
        case .openSystemSettings: platformOps.openSystemSettings(for: permission)
        case nil: break
        }
    }
}

public enum SystemPermissionPrompts {
    /// The prompts that belong on screen right now, given `config` and what `status` reports for
    /// each permission — read by the caller at the moment of asking, since System Settings changes
    /// them behind Mochi's back.
    ///
    /// Accessibility (#111, ADR-0029): whenever it is not granted and a 视频控制 key needs it
    /// (`VideoControl.needsAccessibility(for:)`), at the top of the 幽灵模式 panel and in the
    /// tray — its button the camera's: 请求权限 while Mochi has never asked, 打开系统设置 once it
    /// has. `status` reads Accessibility as trusted or not; `accessibilityRequested` is Mochi's
    /// record of having asked (`SystemPermissionMarker.accessibilityRequested`).
    ///
    /// #105: `downloadsFolderWriteDenied` is the most recent write into the Downloads folder having
    /// been refused (`SystemPermissionMarker.downloadsFolderWriteDenied`) — that folder's only
    /// status. It prompts beside 文件下载位置 while that location is 下载; 每次询问 and a chosen
    /// folder don't rely on the permission. Always 打开系统设置: there is no request to make.
    public static func prompts(
        for config: WidgetConfig, status: (SystemPermission) -> SystemPermissionStatus,
        accessibilityRequested: Bool = false, downloadsFolderWriteDenied: Bool = false
    ) -> [SystemPermissionPrompt] {
        var prompts: [SystemPermissionPrompt] = []
        let accessibility = SystemPermissionStatus.accessibility(
            isTrusted: status(.accessibility) == .authorized, requested: accessibilityRequested)
        if VideoControl.needsAccessibility(for: config), isMissing(accessibility) {
            prompts += [SystemPermissionPrompt.Placement.ghostModePanelTop, .trayMenu].map {
                SystemPermissionPrompt(permission: .accessibility, placement: $0, action: button(for: accessibility))
            }
        }
        // #104: camera and microphone, each at the top of its own 网站 page and judged apart, while
        // the 网页权限 lets pages through and the system has not granted Mochi the device.
        for device in [SystemPermission.camera, .microphone] where pagesMayUse(device, config: config) {
            let deviceStatus = status(device)
            guard isMissing(deviceStatus) else { continue }
            prompts.append(SystemPermissionPrompt(
                permission: device, placement: .websitesPermissionPage, action: button(for: deviceStatus)))
        }
        if downloadsFolderWriteDenied, config.downloadLocation == .downloadsFolder {
            prompts.append(SystemPermissionPrompt(
                permission: .downloadsFolder, placement: .downloadLocation, action: .openSystemSettings))
        }
        return prompts
    }

    /// Whether a permission the system can be asked about is not granted, and so has a prompt.
    private static func isMissing(_ status: SystemPermissionStatus) -> Bool {
        switch status {
        case .notDetermined, .denied, .restricted: true
        case .authorized, .unqueryable: false
        }
    }

    /// The button on its prompt: 请求权限 while the system has never asked, 打开系统设置 once it
    /// has refused, and none when a management policy decides.
    private static func button(for status: SystemPermissionStatus) -> SystemPermissionPrompt.Action? {
        switch status {
        case .notDetermined: .request
        case .denied: .openSystemSettings
        case .restricted, .authorized, .unqueryable: nil
        }
    }

    /// Whether a page can get as far as the system's gate for `device`: a page needs the 网页权限
    /// first, then the 系统权限 (CONTEXT.md), so while the 网页权限 is 拒绝 the system's answer is
    /// beside the point and no prompt shows. The one place this is decided: some page may use
    /// the device whenever the default **or any website's exception** (#109) is not 拒绝.
    private static func pagesMayUse(_ device: SystemPermission, config: WidgetConfig) -> Bool {
        let permission: PagePermission
        switch device {
        case .camera: permission = .camera
        case .microphone: permission = .microphone
        case .accessibility, .downloadsFolder: return false
        }
        return config.pagePermissionDefault(permission) != .deny
            || config.pagePermissionExceptions(permission).contains { $0.setting != .deny }
    }
}
