import Foundation
import Testing

@testable import MochiCore

/// New windows and Popup Windows (#67, ADR-0017): given the widget's mode and one new-window
/// request, what does MochiCore decide — and does anything get handed to the default browser?
@Suite struct OrchestratorNewWindowTests {
    enum Mode: Sendable { case normal, ghost }
    enum Trigger: Sendable { case link, commandLink, script }

    private static let pageURL = URL(string: "https://example.com/login")!

    @Test(arguments: [
        // Normal Mode
        (mode: Mode.normal, trigger: Trigger.link, opener: NewWindowOpener.widget,
         expected: NewWindowDecision.loadInOpener, opensInBrowser: false),
        (mode: .normal, trigger: .link, opener: .popupWindow, expected: .loadInOpener, opensInBrowser: false),
        (mode: .normal, trigger: .commandLink, opener: .widget, expected: .cancel, opensInBrowser: true),
        (mode: .normal, trigger: .commandLink, opener: .popupWindow, expected: .cancel, opensInBrowser: true),
        (mode: .normal, trigger: .script, opener: .widget, expected: .openPopupWindow, opensInBrowser: false),
        (mode: .normal, trigger: .script, opener: .popupWindow, expected: .loadInOpener, opensInBrowser: false),
        // Ghost Mode: nothing opens. The widget's own page doesn't change under a click-through
        // window either; a Popup Window is an ordinary window Ghost Mode doesn't touch, so a
        // request from it may still load in place — that opens nothing.
        (mode: .ghost, trigger: .link, opener: .widget, expected: .cancel, opensInBrowser: false),
        (mode: .ghost, trigger: .link, opener: .popupWindow, expected: .loadInOpener, opensInBrowser: false),
        (mode: .ghost, trigger: .commandLink, opener: .widget, expected: .cancel, opensInBrowser: false),
        (mode: .ghost, trigger: .commandLink, opener: .popupWindow, expected: .cancel, opensInBrowser: false),
        (mode: .ghost, trigger: .script, opener: .widget, expected: .cancel, opensInBrowser: false),
        (mode: .ghost, trigger: .script, opener: .popupWindow, expected: .loadInOpener, opensInBrowser: false),
    ])
    func newWindowDecision(
        _ row: (mode: Mode, trigger: Trigger, opener: NewWindowOpener, expected: NewWindowDecision, opensInBrowser: Bool)
    ) {
        let (fake, orchestrator) = makeWidget(in: row.mode); defer { withExtendedLifetime(orchestrator) {} }
        let request = NewWindowRequest(trigger: Self.trigger(row.trigger), opener: row.opener, url: Self.pageURL)

        #expect(fake.simulateNewWindowRequested(request) == row.expected)
        #expect(fake.urlsOpenedInDefaultBrowser == (row.opensInBrowser ? [Self.pageURL] : []))
        // Settling a request never leaves Ghost Mode.
        #expect((fake.mousePassthroughChanges.last?.enabled ?? false) == (row.mode == .ghost))
    }

    /// A ⌘-click WebKit gives no URL for has nothing to hand over — and still opens nothing.
    @Test func commandClickWithoutAURLOpensNothing() {
        let (fake, orchestrator) = makeWidget(in: .normal); defer { withExtendedLifetime(orchestrator) {} }
        let request = NewWindowRequest(trigger: .linkClick(commandPressed: true), opener: .widget, url: nil)

        #expect(fake.simulateNewWindowRequested(request) == .cancel)
        #expect(fake.urlsOpenedInDefaultBrowser.isEmpty)
    }

    /// Ghost Mode is read when the request arrives, not when the handler was registered.
    @Test func decisionFollowsTheLiveMode() {
        let (fake, orchestrator) = makeWidget(in: .normal); defer { withExtendedLifetime(orchestrator) {} }
        let popup = NewWindowRequest(trigger: .script, opener: .widget, url: Self.pageURL)

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateNewWindowRequested(popup) == .cancel)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateNewWindowRequested(popup) == .openPopupWindow)
    }

    /// The single teardown point closes every Popup Window, for either close entry.
    @Test(arguments: [false, true])
    func closingTheWidgetClosesItsPopupWindows(viaRedButton: Bool) {
        let (fake, orchestrator) = makeWidget(in: .normal)
        if viaRedButton {
            fake.simulateWindowWillClose()
        } else {
            orchestrator.closeWidget()
        }

        #expect(fake.popupWindowsClosedForWindowIDs == [1])
    }

    /// Entering and leaving Ghost Mode leaves Popup Windows alone.
    @Test func ghostModeRoundTripLeavesPopupWindowsOpen() {
        let (fake, orchestrator) = makeWidget(in: .normal); defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(fake.popupWindowsClosedForWindowIDs.isEmpty)
    }

    @Test func aReopenedWidgetAnswersNewWindowRequestsOnItsNewWindow() {
        let (fake, orchestrator) = makeWidget(in: .normal)
        orchestrator.closeWidget()
        orchestrator.openWidget()

        let popup = NewWindowRequest(trigger: .script, opener: .widget, url: Self.pageURL)
        #expect(fake.simulateNewWindowRequested(popup, windowID: 2) == .openPopupWindow)
    }

    @Test(arguments: [
        (policy: WidgetConfig.PopupWindowPolicy.block, allowed: false),
        (policy: .allow, allowed: true),
    ])
    func openingTheWidgetAppliesThePopupWindowSetting(_ row: (policy: WidgetConfig.PopupWindowPolicy, allowed: Bool)) {
        let fake = FakePlatformOps()
        let config = WidgetConfig(url: Self.pageURL).updatingPopupWindowPolicy(row.policy)
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { config })
        orchestrator.start()

        #expect(fake.popupWindowsAllowedChanges.map(\.allowed) == [row.allowed])
        #expect(fake.popupWindowsAllowedChanges.map(\.windowID) == [1])
    }

    private static func trigger(_ trigger: Trigger) -> NewWindowTrigger {
        switch trigger {
        case .link: .linkClick(commandPressed: false)
        case .commandLink: .linkClick(commandPressed: true)
        case .script: .script
        }
    }

    private func makeWidget(in mode: Mode) -> (FakePlatformOps, Orchestrator) {
        let fake = FakePlatformOps()
        let orchestrator = Orchestrator(platformOps: fake, currentConfig: { WidgetConfig(url: Self.pageURL) })
        orchestrator.start()
        if mode == .ghost { fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode) }
        return (fake, orchestrator)
    }
}
