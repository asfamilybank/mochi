import Foundation
import Testing

@testable import MochiCore

@Suite struct EmptyPageHistoryTests {
    @Test func backFromTheOldestPageReturnsToTheEmptyPageTheSessionStartedOn() {
        let step = EmptyPageHistory.backStep(
            isShowingEmptyPage: false, startedOnEmptyPage: true, webViewCanGoBack: false)
        #expect(step == .toEmptyPage)
    }

    /// The web view's own history comes first; the Empty Page is only its floor.
    @Test func backPrefersTheWebViewsOwnHistory() {
        let step = EmptyPageHistory.backStep(
            isShowingEmptyPage: false, startedOnEmptyPage: true, webViewCanGoBack: true)
        #expect(step == .webView)
    }

    @Test func aSessionThatStartedOnAURLHasNoEmptyPageToGoBackTo() {
        let step = EmptyPageHistory.backStep(
            isShowingEmptyPage: false, startedOnEmptyPage: false, webViewCanGoBack: false)
        #expect(step == nil)
    }

    /// Whatever the web view could still go back to, the Empty Page is the bottom of the list.
    @Test(arguments: [false, true])
    func backIsDisabledOnTheEmptyPage(webViewCanGoBack: Bool) {
        let step = EmptyPageHistory.backStep(
            isShowingEmptyPage: true, startedOnEmptyPage: true, webViewCanGoBack: webViewCanGoBack)
        #expect(step == nil)
    }

    @Test func forwardFromTheEmptyPageReturnsToThePageItWasLeftFor() {
        let step = EmptyPageHistory.forwardStep(
            isShowingEmptyPage: true, hasPage: true, webViewCanGoForward: false)
        #expect(step == .fromEmptyPage)
    }

    @Test func forwardIsDisabledOnAnEmptyPageNothingWasEverLoadedFrom() {
        let step = EmptyPageHistory.forwardStep(
            isShowingEmptyPage: true, hasPage: false, webViewCanGoForward: false)
        #expect(step == nil)
    }

    @Test(arguments: [(canGoForward: true, expected: EmptyPageHistory.Step?.some(.webView)), (canGoForward: false, expected: nil)])
    func forwardOnAPageIsTheWebViewsOwn(_ testCase: (canGoForward: Bool, expected: EmptyPageHistory.Step?)) {
        let step = EmptyPageHistory.forwardStep(
            isShowingEmptyPage: false, hasPage: true, webViewCanGoForward: testCase.canGoForward)
        #expect(step == testCase.expected)
    }
}
