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
    @Test(arguments: [SystemPermission.camera, .microphone, .downloadsFolder])
    func otherPermissionsAddNothingYet(_ permission: SystemPermission) {
        for status in [SystemPermissionStatus.notDetermined, .denied, .restricted, .unqueryable] {
            let prompts = SystemPermissionPrompts.prompts(for: WidgetConfig()) { $0 == permission ? status : .authorized }

            #expect(prompts.isEmpty)
        }
    }
}

private extension SystemPermissionPrompt {
    static let accessibilityBelowVideoControl = SystemPermissionPrompt(
        permission: .accessibility, placement: .videoControlSection, action: .openSystemSettings)
}
