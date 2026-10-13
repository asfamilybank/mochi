import Foundation
import Testing

@testable import MochiCore

/// 摄像头与麦克风 on the 网页交互请求 seam (#69), with 网站例外 and Mochi's own prompt (#101,
/// ADR-0027). The rule table itself is `MediaCaptureDecisionTests`; this covers what the
/// orchestration adds: reading the live config and mode, remembering the user's answer — as an
/// exception through `persist`, or as a 「仅这次允许」 held per web view until its next document.
@Suite struct OrchestratorMediaCaptureTests {
    private static let answeredAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let meet = "meet.example.com"

    // MARK: Live config and mode

    /// Settings are read at request time: an edit applies from the next request on.
    @Test func decisionFollowsTheLiveConfig() {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .camera, host: Self.meet)

        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
        store.config.cameraPermission = .allow
        #expect(fake.simulateMediaCaptureRequested(request) == .grant)
        store.config = store.config.updatingPagePermissionException(
            .camera, host: Self.meet, setting: .deny, modifiedAt: Self.answeredAt)
        #expect(fake.simulateMediaCaptureRequested(request) == .deny)
    }

    /// Ghost Mode is read at request time, and only silences the widget's own page: a Popup Window
    /// is an ordinary window, so it is still asked.
    @Test func ghostModeDeniesTheWidgetButStillAsksForAPopupWindow() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let fromWidget = MediaCaptureRequest(device: .microphone, host: Self.meet)
        let fromPopup = MediaCaptureRequest(device: .microphone, host: Self.meet, source: .popupWindow(id: 1))

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateMediaCaptureRequested(fromWidget) == .deny)
        #expect(fake.simulateMediaCaptureRequested(fromPopup) == .ask)
        #expect(fake.mousePassthroughChanges.last?.enabled == true, "asking doesn't leave Ghost Mode")
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.simulateMediaCaptureRequested(fromWidget) == .ask)
    }

    // MARK: Answers that are remembered

    @Test func allowOnThisSiteRemembersAnAllowExceptionSoTheSiteIsNotAskedAgain() {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .camera, host: Self.meet)

        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
        #expect(fake.simulateMediaCapturePromptAnswered(.allowOnThisSite, to: request) == true)

        #expect(store.config.cameraExceptions == [exception(.allow)])
        #expect(store.config.microphoneExceptions.isEmpty)
        #expect(fake.simulateMediaCaptureRequested(request) == .grant)
        fake.simulateNewDocumentCommitted()
        #expect(fake.simulateMediaCaptureRequested(request) == .grant, "an exception outlives the page load")
        let calendar = MediaCaptureRequest(device: .camera, host: "calendar.example.com")
        #expect(fake.simulateMediaCaptureRequested(calendar) == .ask, "only for that exact host")
    }

    @Test func denyRemembersADenyExceptionSoTheSiteIsDeniedWithoutAsking() {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .microphone, host: Self.meet)

        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
        #expect(fake.simulateMediaCapturePromptAnswered(.deny, to: request) == false)

        #expect(store.config.microphoneExceptions == [exception(.deny)])
        #expect(store.config.cameraExceptions.isEmpty)
        #expect(fake.simulateMediaCaptureRequested(request) == .deny)
    }

    /// One prompt for a camera+microphone request; the choice is written for both permissions.
    @Test(arguments: [
        (answer: MediaCapturePromptAnswer.allowOnThisSite, setting: WidgetConfig.MediaCapturePermission.allow, granted: true),
        (answer: .deny, setting: .deny, granted: false),
    ])
    func answeringARequestForBothWritesTwoExceptions(
        _ row: (answer: MediaCapturePromptAnswer, setting: WidgetConfig.MediaCapturePermission, granted: Bool)
    ) {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .cameraAndMicrophone, host: Self.meet)

        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
        #expect(fake.simulateMediaCapturePromptAnswered(row.answer, to: request) == row.granted)
        #expect(store.config.cameraExceptions == [exception(row.setting)])
        #expect(store.config.microphoneExceptions == [exception(row.setting)])
    }

    /// Writing goes through the `persist` transform, on top of whatever is current then — another
    /// site's exception and the defaults are kept.
    @Test func rememberingAnAnswerKeepsTheRestOfTheConfig() {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        store.config.microphonePermission = .deny
        store.config = store.config.updatingPagePermissionException(
            .camera, host: "zoom.example.com", setting: .deny, modifiedAt: Date(timeIntervalSince1970: 0))
        let request = MediaCaptureRequest(device: .camera, host: Self.meet)

        _ = fake.simulateMediaCaptureRequested(request)
        _ = fake.simulateMediaCapturePromptAnswered(.allowOnThisSite, to: request)

        #expect(store.config.cameraExceptions.map(\.host) == [Self.meet, "zoom.example.com"])
        #expect(store.config.microphonePermission == .deny)
    }

    // MARK: 仅这次允许

    @Test func allowThisTimeGrantsUntilTheNextNewDocumentWithoutWritingTheConfig() {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .camera, host: Self.meet)
        let configBefore = store.config

        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
        #expect(fake.simulateMediaCapturePromptAnswered(.allowThisTime, to: request) == true)

        #expect(store.config == configBefore)
        #expect(fake.simulateMediaCaptureRequested(request) == .grant)
        fake.simulateNewDocumentCommitted()
        #expect(fake.simulateMediaCaptureRequested(request) == .ask, "a navigation or reload asks again")
    }

    /// A same-document change (`pushState`, a fragment) is not a new document — the platform
    /// doesn't report it as one — so the grant holds through it and through every other page
    /// signal; only the requesting web view's own new document ends it.
    @Test func allowThisTimeSurvivesEverythingButItsOwnWebViewsNewDocument() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .camera, host: Self.meet)
        _ = fake.simulateMediaCaptureRequested(request)
        _ = fake.simulateMediaCapturePromptAnswered(.allowThisTime, to: request)

        fake.simulatePageTitleChanged("Meeting")
        fake.simulateNavigationFinished()
        fake.simulateNewDocumentCommitted(in: .popupWindow(id: 1))
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)

        #expect(fake.simulateMediaCaptureRequested(request) == .grant)
    }

    /// 「仅这次允许」 belongs to the web view it was given in: a popup's grant is not the widget's.
    @Test func allowThisTimeIsHeldPerWebView() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let fromPopup = MediaCaptureRequest(device: .camera, host: Self.meet, source: .popupWindow(id: 1))
        let fromWidget = MediaCaptureRequest(device: .camera, host: Self.meet)

        _ = fake.simulateMediaCaptureRequested(fromPopup)
        _ = fake.simulateMediaCapturePromptAnswered(.allowThisTime, to: fromPopup)

        #expect(fake.simulateMediaCaptureRequested(fromPopup) == .grant)
        #expect(fake.simulateMediaCaptureRequested(fromWidget) == .ask)
        fake.simulateNewDocumentCommitted(in: .widget)
        #expect(fake.simulateMediaCaptureRequested(fromPopup) == .grant)
        fake.simulateNewDocumentCommitted(in: .popupWindow(id: 1))
        #expect(fake.simulateMediaCaptureRequested(fromPopup) == .ask)
    }

    @Test func allowThisTimeForBothCoversEachDeviceOnItsOwn() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let both = MediaCaptureRequest(device: .cameraAndMicrophone, host: Self.meet)

        _ = fake.simulateMediaCaptureRequested(both)
        _ = fake.simulateMediaCapturePromptAnswered(.allowThisTime, to: both)

        #expect(fake.simulateMediaCaptureRequested(MediaCaptureRequest(device: .camera, host: Self.meet)) == .grant)
        #expect(fake.simulateMediaCaptureRequested(MediaCaptureRequest(device: .microphone, host: Self.meet)) == .grant)
    }

    // MARK: Host-less pages

    /// A `data:`/`file:` page has no host to remember anything under: 允许 / 不允许 cover this
    /// request only, and the next request is asked again.
    @Test(arguments: [
        (answer: MediaCapturePromptAnswer.allowThisTime, granted: true),
        (answer: .deny, granted: false),
    ])
    func answersForAHostlessPageAreNotRemembered(_ row: (answer: MediaCapturePromptAnswer, granted: Bool)) {
        let (fake, store, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .cameraAndMicrophone, host: nil)
        let configBefore = store.config

        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
        #expect(fake.simulateMediaCapturePromptAnswered(row.answer, to: request) == row.granted)

        #expect(store.config == configBefore)
        #expect(fake.simulateMediaCaptureRequested(request) == .ask)
    }

    // MARK: WebKit's own grants (#96)

    /// WebKit keeps a grant through a page's own reload and stops asking; a new document has to
    /// make it forget, or 「仅这次允许」 outlives its page load. The old document is gone, so a
    /// capture in progress is no reason to keep it.
    @Test func aNewDocumentMakesWebKitForgetThatWebViewsGrants() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateNewDocumentCommitted(in: .popupWindow(id: 3))

        #expect(fake.mediaCaptureGrantsForgotten.map(\.source) == [.popupWindow(id: 3)])
        #expect(fake.mediaCaptureGrantsForgotten.map(\.onlyIfIdle) == [false])
    }

    /// A settings edit applies to the next request even where WebKit already granted one — but
    /// a page that is capturing is left alone (forgetting would cut the call off).
    @Test func aSettingsEditMakesWebKitForgetEveryIdleWebViewsGrants() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }

        orchestrator.reapplyConfiguration()

        #expect(fake.mediaCaptureGrantsForgotten.map(\.source) == [nil])
        #expect(fake.mediaCaptureGrantsForgotten.map(\.onlyIfIdle) == [true])
    }

    /// Ghost Mode denies the widget's page; a grant WebKit kept from Normal Mode mustn't slip by.
    /// Popup Windows keep theirs: Ghost Mode doesn't change how they are decided.
    @Test func enteringGhostModeMakesWebKitForgetTheIdleWidgetsGrants() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.mediaCaptureGrantsForgotten.map(\.source) == [.widget])
        #expect(fake.mediaCaptureGrantsForgotten.map(\.onlyIfIdle) == [true])

        fake.simulateHotkeyPressed(DefaultHotkeys.toggleGhostMode)
        #expect(fake.mediaCaptureGrantsForgotten.count == 1, "leaving Ghost Mode loosens nothing")
    }

    // MARK: Reopening

    /// A reopened widget still answers — and its page load starts without the old grants.
    @Test func reopenedWidgetAnswersAndStartsWithoutTheOldGrants() {
        let (fake, _, orchestrator) = makeWidget()
        defer { withExtendedLifetime(orchestrator) {} }
        let request = MediaCaptureRequest(device: .camera, host: Self.meet)
        _ = fake.simulateMediaCaptureRequested(request)
        _ = fake.simulateMediaCapturePromptAnswered(.allowThisTime, to: request)

        orchestrator.closeWidget()
        orchestrator.openWidget()

        #expect(fake.simulateMediaCaptureRequested(request, windowID: 2) == .ask)
        #expect(fake.simulateMediaCapturePromptAnswered(.allowThisTime, to: request, windowID: 2) == true)
        #expect(fake.simulateMediaCaptureRequested(request, windowID: 2) == .grant)
    }

    // MARK: Helpers

    private func exception(_ setting: WidgetConfig.MediaCapturePermission) -> WidgetConfig.PagePermissionException {
        WidgetConfig.PagePermissionException(host: Self.meet, setting: setting, lastModified: Self.answeredAt)
    }

    private final class ConfigBox {
        var config: WidgetConfig
        init(_ config: WidgetConfig) { self.config = config }
    }

    private func makeWidget() -> (FakePlatformOps, ConfigBox, Orchestrator) {
        let fake = FakePlatformOps()
        let store = ConfigBox(WidgetConfig(url: URL(string: "https://example.com")!))
        let orchestrator = Orchestrator(
            platformOps: fake, currentConfig: { store.config }, persist: { store.config = $0(store.config) })
        orchestrator.currentDate = { Self.answeredAt }
        orchestrator.start()
        return (fake, store, orchestrator)
    }
}
