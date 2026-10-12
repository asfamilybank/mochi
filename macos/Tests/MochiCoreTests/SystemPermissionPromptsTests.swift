import Foundation
import Testing

@testable import MochiCore

/// Which 系统权限 prompts the settings panel shows (#98, ADR-0026): given the config and what the
/// system reports for each permission, the prompts and nothing else — a permission already
/// granted shows nothing at all. #98 only carries over #79's one rule: Accessibility, below
/// 视频控制, whenever it is not granted.
@Suite struct SystemPermissionPromptsTests {
    @Test(arguments: [
        // Accessibility reads only trusted or not: every other answer means 打开系统设置.
        (accessibility: SystemPermissionStatus.authorized, expected: [SystemPermissionPrompt]()),
        (accessibility: .denied, expected: [.accessibilityBelowVideoControl]),
        (accessibility: .notDetermined, expected: [.accessibilityBelowVideoControl]),
        (accessibility: .restricted, expected: [.accessibilityBelowVideoControl]),
    ])
    func accessibility(_ row: (accessibility: SystemPermissionStatus, expected: [SystemPermissionPrompt])) {
        let prompts = SystemPermissionPrompts.prompts(for: WidgetConfig()) {
            $0 == .accessibility ? row.accessibility : .authorized
        }

        #expect(prompts == row.expected)
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
    static let accessibilityBelowVideoControl = SystemPermissionPrompt(
        permission: .accessibility, placement: .videoControlSection, action: .openSystemSettings)
}
