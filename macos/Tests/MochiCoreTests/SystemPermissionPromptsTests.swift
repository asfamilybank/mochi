import Foundation
import Testing

@testable import MochiCore

/// Which 系统权限 prompts are on screen (#98, ADR-0026): given the config and what the system
/// reports for each permission, the prompts and nothing else — a permission already granted
/// shows nothing at all.
@Suite struct SystemPermissionPromptsTests {
    /// #111, ADR-0029: Accessibility is needed only for a 视频控制 key bound to a combo with
    /// neither ⌃ nor ⌘ — the kind the system takes for typing and holds back from a listener
    /// without the permission. Taps and double taps (modifier changes) and ⌃/⌘ combos get through
    /// anyway. No Hotkey Forwarding mapping counts: its combos go through Carbon, its taps arrive
    /// as modifier changes.
    @Test(arguments: [
        (video: TriggerKey?.none, mapping: TriggerKey?.none, needed: false),
        (video: .modifierTap(.rightOption), mapping: nil, needed: false),
        (video: .modifierDoubleTap(.rightOption), mapping: nil, needed: false),
        (video: .combo(control | option), mapping: nil, needed: false),
        (video: .combo(command | option), mapping: nil, needed: false),
        (video: .combo(control), mapping: nil, needed: false),
        (video: .combo(command | shift), mapping: nil, needed: false),
        (video: .combo(option), mapping: nil, needed: true),
        (video: .shiftF5, mapping: nil, needed: true),
        (video: .combo(option | shift), mapping: nil, needed: true),
        (video: nil, mapping: .modifierTap(.rightShift), needed: false),
        (video: nil, mapping: .modifierDoubleTap(.rightShift), needed: false),
        (video: nil, mapping: .combo(option), needed: false),
        (video: nil, mapping: .shiftF5, needed: false),
        (video: nil, mapping: .combo(control | option), needed: false),
        (video: .modifierTap(.rightOption), mapping: .combo(option), needed: false),
    ])
    func needsAccessibility(_ row: (video: TriggerKey?, mapping: TriggerKey?, needed: Bool)) {
        var config = WidgetConfig.noVideoKeys.updatingVideoControlTrigger(row.video, for: .seekForward)
        if let trigger = row.mapping {
            config = config.updatingHotkeyMappings([HotkeyMapping(trigger: trigger, pageKeystroke: .space)])
        }

        #expect(VideoControl.needsAccessibility(for: config) == row.needed)
    }

    /// One key that needs it is enough, whichever action it is bound to.
    @Test(arguments: VideoControlAction.allCases)
    func anyVideoKeyCanNeedAccessibility(_ action: VideoControlAction) {
        let config = WidgetConfig(url: nil).updatingVideoControlTrigger(.combo(option), for: action)

        #expect(VideoControl.needsAccessibility(for: config))
    }

    /// The defaults — right ⌥ tapped, right ⌥ / right ⌘ tapped twice (ADR-0024) — need nothing.
    @Test func theDefaultsNeedNoPermission() {
        let prompts = SystemPermissionPrompts.prompts(for: WidgetConfig(url: nil)) {
            $0 == .accessibility ? .denied : .authorized
        }

        #expect(!VideoControl.needsAccessibility(for: WidgetConfig(url: nil)))
        #expect(prompts.isEmpty)
    }

    /// The system answers no more than "trusted or not" for Accessibility (ADR-0029), so whether
    /// it has ever asked is Mochi's own record: not trusted and never requested is 未询问, not
    /// trusted after a request is 已拒绝.
    @Test(arguments: [
        (trusted: false, requested: false, status: SystemPermissionStatus.notDetermined),
        (trusted: false, requested: true, status: .denied),
        (trusted: true, requested: false, status: .authorized),
        (trusted: true, requested: true, status: .authorized),
    ])
    func accessibilityStatus(_ row: (trusted: Bool, requested: Bool, status: SystemPermissionStatus)) {
        #expect(SystemPermissionStatus.accessibility(isTrusted: row.trusted, requested: row.requested) == row.status)
    }

    /// While something needs Accessibility and it is not granted: one prompt at the top of the
    /// 热键 panel and one in the tray, its button like the camera's — 请求权限 while Mochi has
    /// never asked, 打开系统设置 once it has (#111). Granted, or not needed, nothing. The platform
    /// reads Accessibility as `.authorized` or `.denied` only: trusted or not.
    @Test(arguments: [
        (needed: true, trusted: false, requested: false, shown: true, action: SystemPermissionPrompt.Action?.some(.request)),
        (needed: true, trusted: false, requested: true, shown: true, action: .openSystemSettings),
        (needed: true, trusted: true, requested: false, shown: false, action: nil),
        (needed: true, trusted: true, requested: true, shown: false, action: nil),
        (needed: false, trusted: false, requested: false, shown: false, action: nil),
        (needed: false, trusted: false, requested: true, shown: false, action: nil),
        (needed: false, trusted: true, requested: true, shown: false, action: nil),
    ])
    func accessibility(
        _ row: (needed: Bool, trusted: Bool, requested: Bool, shown: Bool, action: SystemPermissionPrompt.Action?)
    ) {
        let config = WidgetConfig(url: nil)
            .updatingVideoControlTrigger(.combo(row.needed ? option : control | option), for: .seekForward)

        let prompts = SystemPermissionPrompts.prompts(
            for: config, status: { $0 == .accessibility && !row.trusted ? .denied : .authorized },
            accessibilityRequested: row.requested)

        let expected = row.shown
            ? [SystemPermissionPrompt.Placement.hotkeysPanelTop, .trayMenu].map {
                SystemPermissionPrompt(permission: .accessibility, placement: $0, action: row.action)
            }
            : []
        #expect(prompts == expected)
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

    // MARK: 网站例外 (#109)

    /// With website exceptions a page gets past the 网页权限 whenever the default **or any
    /// exception** is not 拒绝 — so a 拒绝 default with one website allowed (or asked) still needs
    /// the system's gate, and only a 拒绝 default with nothing but 拒绝 exceptions shows nothing.
    @Test(arguments: [SystemPermission.camera, .microphone], [
        (default: WidgetConfig.MediaCapturePermission.deny, exceptions: [WidgetConfig.MediaCapturePermission.allow], shown: true),
        (default: .deny, exceptions: [.ask], shown: true),
        (default: .deny, exceptions: [.deny, .allow], shown: true),
        (default: .deny, exceptions: [.deny], shown: false),
        (default: .deny, exceptions: [.deny, .deny], shown: false),
        (default: .deny, exceptions: [], shown: false),
        (default: .ask, exceptions: [.deny], shown: true),
        (default: .allow, exceptions: [.deny, .deny], shown: true),
    ])
    func websiteExceptions(
        _ device: SystemPermission,
        _ row: (default: WidgetConfig.MediaCapturePermission, exceptions: [WidgetConfig.MediaCapturePermission], shown: Bool)
    ) {
        let permission: PagePermission = device == .camera ? .camera : .microphone
        let other: PagePermission = device == .camera ? .microphone : .camera
        var config = WidgetConfig()
            .updatingCameraPermission(permission == .camera ? row.default : .deny)
            .updatingMicrophonePermission(permission == .microphone ? row.default : .deny)
        for (index, setting) in row.exceptions.enumerated() {
            config = config.updatingPagePermissionException(
                permission, host: "site\(index).example.com", setting: setting, modifiedAt: Date(timeIntervalSince1970: 0))
        }
        // The other device's exceptions say nothing about this one's prompt.
        config = config.updatingPagePermissionException(
            other, host: "other.example.com", setting: .allow, modifiedAt: Date(timeIntervalSince1970: 0))

        let prompts = SystemPermissionPrompts.prompts(for: config) { $0 == device ? .denied : .authorized }

        let expected = row.shown
            ? [SystemPermissionPrompt(permission: device, placement: .websitesPermissionPage, action: .openSystemSettings)]
            : []
        #expect(prompts == expected)
    }
}

private extension WidgetConfig {
    /// Every 视频控制 key unbound.
    static let noVideoKeys = VideoControlAction.allCases.reduce(WidgetConfig(url: nil)) {
        $0.updatingVideoControlTrigger(nil, for: $1)
    }
}

private extension TriggerKey {
    /// P with `modifiers` (Carbon bits). `0x23` is `kVK_ANSI_P`.
    static func combo(_ modifiers: UInt32) -> TriggerKey {
        .keystroke(Hotkey(keyCode: 0x23, modifierFlags: modifiers))
    }

    /// ⇧F5 — ⇧ alone is allowed with the F-keys (ADR-0023). `0x60` is `kVK_F5`.
    static let shiftF5 = TriggerKey.keystroke(Hotkey(keyCode: 0x60, modifierFlags: shift))
}

/// Carbon's modifier bits, as `Hotkey.modifierFlags` holds them.
private let control: UInt32 = 0x1000
private let option: UInt32 = 0x0800
private let shift: UInt32 = 0x0200
private let command: UInt32 = 0x0100

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
