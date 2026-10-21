import Foundation
import Testing

@testable import MochiCore

/// The 网页交互请求 seam (#66): given the widget's mode and one page-initiated request, what does
/// MochiCore decide? Ghost Mode's "不打扰" rule (CONTEXT.md) is pinned here — no UI, no leaving
/// Ghost Mode, and the page is never left waiting.
@Suite struct OrchestratorWebInteractionTests {
    enum Mode: Sendable { case normal, float, floatHidden, ghost }

    private static let dialogKinds: [JavaScriptDialogKind] = [.alert, .confirm, .prompt(defaultText: "默认")]

    @Test(arguments: [
        (mode: Mode.normal, kindIndex: 0, expected: JavaScriptDialogDecision.presentSheet),
        (mode: .normal, kindIndex: 1, expected: .presentSheet),
        (mode: .normal, kindIndex: 2, expected: .presentSheet),
        // Float Mode is an ordinary window for the page (#147, ADR-0035): it asks as usual.
        (mode: .float, kindIndex: 0, expected: .presentSheet),
        (mode: .float, kindIndex: 1, expected: .presentSheet),
        (mode: .float, kindIndex: 2, expected: .presentSheet),
        // Hidden, Float Mode too is 不打扰 (#148): nothing may pop up on a window nobody can see.
        (mode: .floatHidden, kindIndex: 0, expected: .settleWithoutUI),
        (mode: .floatHidden, kindIndex: 1, expected: .settleWithoutUI),
        (mode: .floatHidden, kindIndex: 2, expected: .settleWithoutUI),
        (mode: .ghost, kindIndex: 0, expected: .settleWithoutUI),
        (mode: .ghost, kindIndex: 1, expected: .settleWithoutUI),
        (mode: .ghost, kindIndex: 2, expected: .settleWithoutUI),
    ])
    func javaScriptDialogDecision(_ row: (mode: Mode, kindIndex: Int, expected: JavaScriptDialogDecision)) {
        let (fake, orchestrator) = makeWidget(in: row.mode); defer { withExtendedLifetime(orchestrator) {} }
        let request = JavaScriptDialogRequest(kind: Self.dialogKinds[row.kindIndex], message: "hi", host: "example.com")

        #expect(fake.simulateJavaScriptDialogRequested(request) == row.expected)
        #expect(fake.passthroughAfterRequest == (row.mode == .ghost || row.mode == .floatHidden))
    }

    @Test(arguments: [
        (mode: Mode.normal, multiple: false, directories: false, expected: FileUploadDecision.presentOpenPanel),
        (mode: .normal, multiple: true, directories: true, expected: .presentOpenPanel),
        (mode: .float, multiple: false, directories: false, expected: .presentOpenPanel),
        (mode: .floatHidden, multiple: false, directories: false, expected: .cancel),
        (mode: .ghost, multiple: false, directories: false, expected: .cancel),
        (mode: .ghost, multiple: true, directories: true, expected: .cancel),
    ])
    func fileUploadDecision(_ row: (mode: Mode, multiple: Bool, directories: Bool, expected: FileUploadDecision)) {
        let (fake, orchestrator) = makeWidget(in: row.mode); defer { withExtendedLifetime(orchestrator) {} }
        let request = FileUploadRequest(allowsMultipleSelection: row.multiple, allowsDirectories: row.directories)

        #expect(fake.simulateFileUploadRequested(request) == row.expected)
        #expect(fake.passthroughAfterRequest == (row.mode == .ghost || row.mode == .floatHidden))
    }

    /// Ghost Mode is read at request time, not when the handler was registered.
    @Test func decisionFollowsTheLiveModeAcrossToggles() {
        let (fake, orchestrator) = makeWidget(in: .normal); defer { withExtendedLifetime(orchestrator) {} }
        let alert = JavaScriptDialogRequest(kind: .alert, message: "", host: nil)

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateJavaScriptDialogRequested(alert) == .settleWithoutUI)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateJavaScriptDialogRequested(alert) == .presentSheet)
    }

    /// A reopened widget registers the seam again on its new window.
    @Test func reopenedWidgetStillAnswersRequests() {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig(url: URL(string: "https://example.com")!) })
        orchestrator.start()
        orchestrator.closeWidget()
        orchestrator.openWidget()

        let upload = FileUploadRequest(allowsMultipleSelection: false, allowsDirectories: false)
        #expect(fake.simulateFileUploadRequested(upload, windowID: 2) == .presentOpenPanel)
    }

    @Test(arguments: [
        (host: String?.some("example.com"), title: "「example.com」网页显示"),
        (host: nil, title: "此网页显示"),
        (host: "", title: "此网页显示"),
    ])
    func dialogSheetTitleNamesTheHost(_ row: (host: String?, title: String)) {
        #expect(JavaScriptDialogRequest(kind: .alert, message: "", host: row.host).sheetTitle == row.title)
    }

    private func makeWidget(in mode: Mode) -> (FakePlatformOps, Orchestrator) {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig(url: URL(string: "https://example.com")!) })
        orchestrator.start()
        switch mode {
        case .normal: break
        case .float: fake.simulateHotkeyPressed(DefaultHotkeys.toggleFloatMode)
        case .floatHidden:
            fake.simulateHotkeyPressed(DefaultHotkeys.toggleFloatMode)
            fake.simulateHotkeyPressed(DefaultHotkeys.hideWidget)
        case .ghost: fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        }
        return (fake, orchestrator)
    }
}

private extension FakePlatformOps {
    /// Whether the widget is still click-through after the request — i.e. still in Ghost Mode, or
    /// still Hidden.
    var passthroughAfterRequest: Bool { mousePassthroughChanges.last?.enabled ?? false }
}
