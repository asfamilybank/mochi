import Foundation
import Testing

@testable import MochiCore

/// 摄像头与麦克风授权 (#69) on the 网页交互请求 seam: setting value × device type × Normal/Ghost.
/// Ghost Mode denies everything without a prompt (CONTEXT.md "不打扰"); a camera+microphone
/// request takes the stricter of the two settings (拒绝 > 询问 > 允许).
@Suite struct OrchestratorMediaCaptureTests {
    enum Mode: Sendable { case normal, ghost }
    typealias Permission = WidgetConfig.MediaCapturePermission

    @Test(arguments: [
        // Camera only — the microphone setting must not matter.
        (mode: Mode.normal, device: MediaCaptureDevice.camera, camera: Permission.ask, microphone: Permission.deny, expected: MediaCaptureDecision.prompt),
        (mode: .normal, device: .camera, camera: .allow, microphone: .deny, expected: .grant),
        (mode: .normal, device: .camera, camera: .deny, microphone: .allow, expected: .deny),
        // Microphone only — the camera setting must not matter.
        (mode: .normal, device: .microphone, camera: .deny, microphone: .ask, expected: .prompt),
        (mode: .normal, device: .microphone, camera: .deny, microphone: .allow, expected: .grant),
        (mode: .normal, device: .microphone, camera: .allow, microphone: .deny, expected: .deny),
        // Both — the stricter setting wins.
        (mode: .normal, device: .cameraAndMicrophone, camera: .allow, microphone: .allow, expected: .grant),
        (mode: .normal, device: .cameraAndMicrophone, camera: .ask, microphone: .ask, expected: .prompt),
        (mode: .normal, device: .cameraAndMicrophone, camera: .deny, microphone: .deny, expected: .deny),
        (mode: .normal, device: .cameraAndMicrophone, camera: .allow, microphone: .ask, expected: .prompt),
        (mode: .normal, device: .cameraAndMicrophone, camera: .ask, microphone: .allow, expected: .prompt),
        (mode: .normal, device: .cameraAndMicrophone, camera: .allow, microphone: .deny, expected: .deny),
        (mode: .normal, device: .cameraAndMicrophone, camera: .deny, microphone: .ask, expected: .deny),
        // Ghost Mode — always deny, whatever the settings.
        (mode: .ghost, device: .camera, camera: .allow, microphone: .allow, expected: .deny),
        (mode: .ghost, device: .camera, camera: .ask, microphone: .ask, expected: .deny),
        (mode: .ghost, device: .microphone, camera: .allow, microphone: .allow, expected: .deny),
        (mode: .ghost, device: .microphone, camera: .ask, microphone: .ask, expected: .deny),
        (mode: .ghost, device: .cameraAndMicrophone, camera: .allow, microphone: .allow, expected: .deny),
        (mode: .ghost, device: .cameraAndMicrophone, camera: .ask, microphone: .allow, expected: .deny),
    ])
    func mediaCaptureDecision(
        _ row: (mode: Mode, device: MediaCaptureDevice, camera: Permission, microphone: Permission, expected: MediaCaptureDecision)
    ) {
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        config.cameraPermission = row.camera
        config.microphonePermission = row.microphone
        let snapshot = config
        let (fake, orchestrator) = makeWidget(in: row.mode, config: { snapshot })
        defer { withExtendedLifetime(orchestrator) {} }

        let request = MediaCaptureRequest(device: row.device, host: "meet.example.com")
        #expect(fake.simulateMediaCaptureRequested(request) == row.expected)
        #expect(fake.passthroughAfterMediaRequest == (row.mode == .ghost))
    }

    /// Settings are read at request time: an edit applies from the next request on.
    @Test func decisionFollowsTheLiveConfig() {
        let store = ConfigBox(WidgetConfig(url: URL(string: "https://example.com")!))
        let (fake, orchestrator) = makeWidget(in: .normal, config: { store.config })
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .camera, host: nil)

        #expect(fake.simulateMediaCaptureRequested(request) == .prompt)
        store.config.cameraPermission = .allow
        #expect(fake.simulateMediaCaptureRequested(request) == .grant)
        store.config.cameraPermission = .deny
        #expect(fake.simulateMediaCaptureRequested(request) == .deny)
    }

    /// Ghost Mode is read at request time, not when the handler was registered.
    @Test func decisionFollowsTheLiveModeAcrossToggles() {
        var config = WidgetConfig(url: URL(string: "https://example.com")!)
        config.microphonePermission = .allow
        let snapshot = config
        let (fake, orchestrator) = makeWidget(in: .normal, config: { snapshot })
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .microphone, host: nil)

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateMediaCaptureRequested(request) == .deny)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateMediaCaptureRequested(request) == .grant)
    }

    @Test func reopenedWidgetStillAnswersMediaCaptureRequests() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig(url: URL(string: "https://example.com")!) })
        orchestrator.start()
        orchestrator.closeWidget()
        orchestrator.openWidget()

        let request = MediaCaptureRequest(device: .cameraAndMicrophone, host: nil)
        #expect(fake.simulateMediaCaptureRequested(request, windowID: 2) == .prompt)
    }

    private final class ConfigBox {
        var config: WidgetConfig
        init(_ config: WidgetConfig) { self.config = config }
    }

    private func makeWidget(in mode: Mode, config: @escaping () -> WidgetConfig) -> (FakePlatformOps, Orchestrator) {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: config)
        orchestrator.start()
        if mode == .ghost { fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode) }
        return (fake, orchestrator)
    }
}

private extension FakePlatformOps {
    /// Whether the widget is still click-through after the request — i.e. still in Ghost Mode.
    var passthroughAfterMediaRequest: Bool { mousePassthroughChanges.last?.enabled ?? false }
}
