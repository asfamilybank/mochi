import Foundation
import Testing

@testable import MochiCore

/// 网页权限 decisions (#101, ADR-0027): default × exception × device × source × Ghost Mode ×
/// 「仅这次允许」 × host-less page. Exceptions are always on `meet.example.com`; `host` says who asks.
@Suite struct MediaCaptureDecisionTests {
    typealias Permission = WidgetConfig.MediaCapturePermission

    struct Row: Sendable, CustomTestStringConvertible {
        var device: MediaCaptureDevice = .camera
        var host: String? = "meet.example.com"
        var cameraDefault: Permission = .ask
        var microphoneDefault: Permission = .ask
        var cameraException: Permission? = nil
        var microphoneException: Permission? = nil
        var source: WebViewSource = .widget
        var ghost = false
        /// 「仅这次允许」 grants for `meet.example.com` in the requesting web view.
        var grantedThisTime: Set<PagePermission> = []
        var expected: MediaCaptureDecision

        var testDescription: String {
            "\(device) from \(host ?? "nil") (\(source)\(ghost ? ", ghost" : "")): defaults \(cameraDefault)/\(microphoneDefault), "
                + "exceptions \(cameraException.map { "\($0)" } ?? "-")/\(microphoneException.map { "\($0)" } ?? "-"), "
                + "this time \(grantedThisTime.map(\.rawValue).sorted()) → \(expected)"
        }
    }

    @Test(arguments: [
        // Defaults only — each permission's own default, the other's doesn't matter.
        Row(cameraDefault: .ask, microphoneDefault: .deny, expected: .ask),
        Row(cameraDefault: .allow, microphoneDefault: .deny, expected: .grant),
        Row(cameraDefault: .deny, microphoneDefault: .allow, expected: .deny),
        Row(device: .microphone, cameraDefault: .deny, microphoneDefault: .allow, expected: .grant),
        Row(device: .microphone, cameraDefault: .allow, microphoneDefault: .ask, expected: .ask),
        // An exception overrides the default, in either direction.
        Row(cameraDefault: .ask, cameraException: .allow, expected: .grant),
        Row(cameraDefault: .allow, cameraException: .deny, expected: .deny),
        Row(cameraDefault: .deny, cameraException: .ask, expected: .ask),
        Row(device: .microphone, microphoneDefault: .deny, microphoneException: .allow, expected: .grant),
        // …but only its own permission's, and only for its exact host.
        Row(cameraDefault: .ask, microphoneException: .allow, expected: .ask),
        Row(host: "calendar.example.com", cameraDefault: .ask, cameraException: .allow, expected: .ask),
        Row(host: "example.com", cameraDefault: .deny, cameraException: .allow, expected: .deny),
        Row(host: "MEET.Example.com", cameraDefault: .ask, cameraException: .allow, expected: .grant),
        // A host-less page (`data:`, `file:`) only ever gets the default.
        Row(host: nil, cameraDefault: .deny, cameraException: .allow, expected: .deny),
        Row(host: nil, cameraDefault: .allow, expected: .grant),
        Row(host: nil, cameraDefault: .ask, grantedThisTime: [.camera], expected: .ask),
        // Both — the stricter of the two, each from its own exception or default.
        Row(device: .cameraAndMicrophone, cameraDefault: .allow, microphoneDefault: .allow, expected: .grant),
        Row(device: .cameraAndMicrophone, cameraDefault: .ask, microphoneDefault: .ask, expected: .ask),
        Row(device: .cameraAndMicrophone, cameraDefault: .deny, microphoneDefault: .deny, expected: .deny),
        Row(device: .cameraAndMicrophone, cameraException: .allow, microphoneException: .deny, expected: .deny),
        Row(device: .cameraAndMicrophone, cameraException: .allow, expected: .ask),
        Row(device: .cameraAndMicrophone, cameraException: .allow, microphoneException: .allow, expected: .grant),
        Row(
            device: .cameraAndMicrophone, cameraDefault: .deny, microphoneDefault: .allow, cameraException: .allow,
            expected: .grant),
        Row(device: .cameraAndMicrophone, cameraDefault: .allow, microphoneDefault: .allow, microphoneException: .ask, expected: .ask),
        // Ghost Mode: the widget's page is denied whatever the settings; a Popup Window is asked as usual.
        Row(cameraException: .allow, ghost: true, expected: .deny),
        Row(device: .cameraAndMicrophone, cameraDefault: .allow, microphoneDefault: .allow, ghost: true, expected: .deny),
        Row(cameraException: .allow, source: .popupWindow(id: 1), ghost: true, expected: .grant),
        Row(cameraDefault: .ask, source: .popupWindow(id: 1), ghost: true, expected: .ask),
        Row(cameraDefault: .deny, source: .popupWindow(id: 1), ghost: true, expected: .deny),
        Row(cameraDefault: .ask, source: .popupWindow(id: 1), expected: .ask),
        // 「仅这次允许」 turns 询问 into 允许 for the permission it was given for…
        Row(cameraDefault: .ask, grantedThisTime: [.camera], expected: .grant),
        Row(cameraDefault: .ask, grantedThisTime: [.microphone], expected: .ask),
        Row(device: .cameraAndMicrophone, grantedThisTime: [.camera], expected: .ask),
        Row(device: .cameraAndMicrophone, grantedThisTime: [.camera, .microphone], expected: .grant),
        Row(device: .cameraAndMicrophone, cameraDefault: .allow, grantedThisTime: [.microphone], expected: .grant),
        // …never over a 拒绝, never for another host, and never past Ghost Mode on the widget.
        Row(cameraException: .deny, grantedThisTime: [.camera], expected: .deny),
        Row(cameraDefault: .deny, grantedThisTime: [.camera], expected: .deny),
        Row(host: "calendar.example.com", grantedThisTime: [.camera], expected: .ask),
        Row(ghost: true, grantedThisTime: [.camera], expected: .deny),
        Row(source: .popupWindow(id: 1), ghost: true, grantedThisTime: [.camera], expected: .grant),
    ])
    func decision(_ row: Row) {
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        config.cameraPermission = row.cameraDefault
        config.microphonePermission = row.microphoneDefault
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        config = config.updatingPagePermissionException(
            .camera, host: "meet.example.com", setting: row.cameraException, modifiedAt: date)
        config = config.updatingPagePermissionException(
            .microphone, host: "meet.example.com", setting: row.microphoneException, modifiedAt: date)
        let grants = Set(row.grantedThisTime.map { MediaCaptureGrant(host: "meet.example.com", permission: $0) })

        let request = MediaCaptureRequest(device: row.device, host: row.host, source: row.source)
        let decision = MediaCaptureDecision.deciding(
            request, config: config, isGhostModeActive: row.ghost, grantedThisTime: grants)
        #expect(decision == row.expected)
    }

    // MARK: - The prompt

    @Test(arguments: [
        (device: MediaCaptureDevice.camera, title: "“meet.google.com”想使用你的摄像头"),
        (device: .microphone, title: "“meet.google.com”想使用你的麦克风"),
        (device: .cameraAndMicrophone, title: "“meet.google.com”想使用你的摄像头和麦克风"),
    ])
    func promptNamesTheHostAndTheDeviceWithChromesThreeChoices(_ row: (device: MediaCaptureDevice, title: String)) {
        let prompt = MediaCapturePrompt(for: MediaCaptureRequest(device: row.device, host: "meet.google.com"))
        #expect(prompt.title == row.title)
        #expect(prompt.choices.map(\.title) == ["访问此网站时允许", "仅这次允许", "不允许"])
        #expect(prompt.choices.map(\.answer) == [.allowOnThisSite, .allowThisTime, .deny])
    }

    /// Nothing to remember a host-less page under, so nothing that sounds remembered is offered.
    @Test func promptForAHostlessPageOffersOnlyAllowAndDeny() {
        let prompt = MediaCapturePrompt(for: MediaCaptureRequest(device: .camera, host: ""))
        #expect(prompt.title == "此网页想使用你的摄像头")
        #expect(prompt.choices.map(\.title) == ["允许", "不允许"])
        #expect(prompt.choices.map(\.answer) == [.allowThisTime, .deny])
    }
}
