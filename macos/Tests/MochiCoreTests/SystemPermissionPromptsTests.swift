import Foundation
import Testing

@testable import MochiCore

/// Which 系统权限 prompts are on screen (#98, ADR-0026): given the config and what the system
/// reports for each permission, the prompts and nothing else — a permission already granted
/// shows nothing at all.
@Suite struct SystemPermissionPromptsTests {
    /// #103: Accessibility is asked about only where something needs it — a 视频控制 key, or a
    /// Hotkey Forwarding mapping set off by a tap or a double tap, both heard by listening to
    /// other apps' keys. Then, until it is granted, one prompt at the top of the 幽灵模式 panel
    /// and one in the tray; the system answers nothing finer than "trusted or not", so the
    /// button is always 打开系统设置.
    @Test(arguments: [
        (videoKeys: true, mapping: TriggerKind?.none, accessibility: SystemPermissionStatus.denied, prompted: true),
        (videoKeys: true, mapping: nil, accessibility: .notDetermined, prompted: true),
        (videoKeys: true, mapping: nil, accessibility: .restricted, prompted: true),
        (videoKeys: true, mapping: nil, accessibility: .authorized, prompted: false),
        (videoKeys: false, mapping: .tap, accessibility: .denied, prompted: true),
        (videoKeys: false, mapping: .tap, accessibility: .authorized, prompted: false),
        (videoKeys: false, mapping: .doubleTap, accessibility: .denied, prompted: true),
        (videoKeys: false, mapping: .doubleTap, accessibility: .authorized, prompted: false),
        // A combo mapping goes through Carbon, which needs no permission.
        (videoKeys: false, mapping: .combo, accessibility: .denied, prompted: false),
        (videoKeys: false, mapping: nil, accessibility: .denied, prompted: false),
        (videoKeys: true, mapping: .tap, accessibility: .denied, prompted: true),
        (videoKeys: true, mapping: .tap, accessibility: .authorized, prompted: false),
    ])
    func accessibility(
        _ row: (videoKeys: Bool, mapping: TriggerKind?, accessibility: SystemPermissionStatus, prompted: Bool)
    ) {
        var config = row.videoKeys ? WidgetConfig(url: nil) : .noVideoKeys
        if let kind = row.mapping {
            config = config.updatingHotkeyMappings([HotkeyMapping(trigger: .example(of: kind), pageKeystroke: .space)])
        }

        let prompts = SystemPermissionPrompts.prompts(for: config) {
            $0 == .accessibility ? row.accessibility : .authorized
        }

        #expect(prompts == (row.prompted ? [.accessibilityAtGhostModePanelTop, .accessibilityInTray] : []))
    }

    /// A 视频控制 key bound to a combo is still heard by listening, not through Carbon — it needs
    /// Accessibility as much as a tap does.
    @Test func aVideoKeyBoundToACombo() {
        let config = WidgetConfig.noVideoKeys
            .updatingVideoControlTrigger(.example(of: .combo), for: .togglePlayback)

        let prompts = SystemPermissionPrompts.prompts(for: config) { _ in .denied }

        #expect(prompts.filter { $0.permission == .accessibility }
            == [.accessibilityAtGhostModePanelTop, .accessibilityInTray])
    }

    /// Other permissions have no prompt of their own yet — whatever they read, they add nothing.
    @Test(arguments: [SystemPermission.downloadsFolder])
    func otherPermissionsAddNothingYet(_ permission: SystemPermission) {
        for status in [SystemPermissionStatus.notDetermined, .denied, .restricted, .unqueryable] {
            let prompts = SystemPermissionPrompts.prompts(for: WidgetConfig()) { $0 == permission ? status : .authorized }

            #expect(prompts.isEmpty)
        }
    }

    // MARK: 摄像头 / 麦克风 (#104)

    /// A page can only use the camera or microphone through both gates — 网页权限 then 系统权限
    /// (CONTEXT.md). So the prompt shows only while the 网页权限 lets pages through (not 拒绝)
    /// and the system has not: 未询问 offers 请求权限, 已拒绝 打开系统设置, 受限制 no button.
    @Test(arguments: [SystemPermission.camera, .microphone], [
        (system: SystemPermissionStatus.notDetermined, page: WidgetConfig.MediaCapturePermission.ask, shown: true, action: SystemPermissionPrompt.Action?.some(.request)),
        (system: .notDetermined, page: .allow, shown: true, action: .request),
        (system: .notDetermined, page: .deny, shown: false, action: nil),
        (system: .denied, page: .ask, shown: true, action: .openSystemSettings),
        (system: .denied, page: .allow, shown: true, action: .openSystemSettings),
        (system: .denied, page: .deny, shown: false, action: nil),
        (system: .restricted, page: .ask, shown: true, action: nil),
        (system: .restricted, page: .allow, shown: true, action: nil),
        (system: .restricted, page: .deny, shown: false, action: nil),
        (system: .authorized, page: .ask, shown: false, action: nil),
        (system: .authorized, page: .allow, shown: false, action: nil),
        (system: .authorized, page: .deny, shown: false, action: nil),
    ])
    func cameraAndMicrophone(
        _ device: SystemPermission,
        _ row: (system: SystemPermissionStatus, page: WidgetConfig.MediaCapturePermission, shown: Bool, action: SystemPermissionPrompt.Action?)
    ) {
        var config = WidgetConfig()
        config.cameraPermission = device == .camera ? row.page : .ask
        config.microphonePermission = device == .microphone ? row.page : .ask

        let prompts = SystemPermissionPrompts.prompts(for: config) { $0 == device ? row.system : .authorized }

        let expected = row.shown
            ? [SystemPermissionPrompt(permission: device, placement: .websitesPermissionPage, action: row.action)]
            : []
        #expect(prompts == expected)
    }

    /// Each device stands on its own: one's 网页权限 or system answer says nothing about the other's.
    @Test func cameraAndMicrophoneAreJudgedApart() {
        var config = WidgetConfig()
        config.cameraPermission = .allow
        config.microphonePermission = .ask
        let statuses: [SystemPermission: SystemPermissionStatus] = [.camera: .notDetermined, .microphone: .denied]

        let both = SystemPermissionPrompts.prompts(for: config) { statuses[$0] ?? .authorized }
        config.cameraPermission = .deny
        let microphoneOnly = SystemPermissionPrompts.prompts(for: config) { statuses[$0] ?? .authorized }

        #expect(both == [
            SystemPermissionPrompt(permission: .camera, placement: .websitesPermissionPage, action: .request),
            SystemPermissionPrompt(permission: .microphone, placement: .websitesPermissionPage, action: .openSystemSettings),
        ])
        #expect(microphoneOnly == [
            SystemPermissionPrompt(permission: .microphone, placement: .websitesPermissionPage, action: .openSystemSettings),
        ])
    }
}

private extension SystemPermissionPrompt {
    static let accessibilityAtGhostModePanelTop = SystemPermissionPrompt(
        permission: .accessibility, placement: .ghostModePanelTop, action: .openSystemSettings)
    static let accessibilityInTray = SystemPermissionPrompt(
        permission: .accessibility, placement: .trayMenu, action: .openSystemSettings)
}

private extension WidgetConfig {
    /// Every 视频控制 key unbound.
    static let noVideoKeys = VideoControlAction.allCases.reduce(WidgetConfig(url: nil)) {
        $0.updatingVideoControlTrigger(nil, for: $1)
    }
}

private extension TriggerKey {
    static func example(of kind: TriggerKind) -> TriggerKey {
        switch kind {
        case .tap: .modifierTap(.rightShift)
        case .doubleTap: .modifierDoubleTap(.rightShift)
        case .combo: .keystroke(Hotkey(keyCode: 0x0E, modifierFlags: 0x0800))  // ⌥E
        }
    }
}

private extension Hotkey {
    static let space = Hotkey(keyCode: 0x31, modifierFlags: 0)
}

// MARK: Downloads folder (#105)

/// The Downloads folder has no status to read: its prompt hangs on the most recent write into it
/// (`SystemPermissionMarker.downloadsFolderWriteDenied`), and only where that folder is the
/// download location — 每次询问 and a chosen folder don't depend on its permission.
extension SystemPermissionPromptsTests {
    static let chosenFolder = URL(fileURLWithPath: "/fake/Chosen", isDirectory: true)

    @Test(arguments: [
        (location: DownloadLocation.downloadsFolder, writeDenied: true, expected: [SystemPermissionPrompt.downloadsFolderBesideDownloadLocation]),
        (location: .downloadsFolder, writeDenied: false, expected: []),
        (location: .askEachTime, writeDenied: true, expected: []),
        (location: .askEachTime, writeDenied: false, expected: []),
        (location: .folder(chosenFolder), writeDenied: true, expected: []),
        (location: .folder(chosenFolder), writeDenied: false, expected: []),
    ])
    func downloadsFolder(_ row: (location: DownloadLocation, writeDenied: Bool, expected: [SystemPermissionPrompt])) {
        let prompts = SystemPermissionPrompts.prompts(
            for: WidgetConfig().updatingDownloadLocation(row.location), status: { _ in .authorized },
            downloadsFolderWriteDenied: row.writeDenied)

        #expect(prompts == row.expected)
    }
}

private extension SystemPermissionPrompt {
    static let downloadsFolderBesideDownloadLocation = SystemPermissionPrompt(
        permission: .downloadsFolder, placement: .downloadLocation, action: .openSystemSettings)
}
