import Foundation
import Testing

@testable import MochiCore

@Suite struct AddressFieldPresenterTests {
    private static let url = "https://example.com/page"
    private static let host = "example.com"

    @Test func loadingShowsTheURLWhileNobodyIsEditing() {
        for isHovering in [false, true] {
            let state = AddressFieldPresenter.displayState(
                isLoading: true, isHovering: isHovering, isEditing: false,
                pageTitle: "Title", urlString: Self.url, host: Self.host
            )
            #expect(state.text == Self.url)
            #expect(state.isEditable == false)
        }
    }

    /// A heavy page can keep loading for many seconds; refusing to let the address be retyped
    /// until it settles is what every other browser doesn't do.
    @Test func editingOutranksLoadingSoTheAddressStaysTypeableMidNavigation() {
        for isHovering in [false, true] {
            let state = AddressFieldPresenter.displayState(
                isLoading: true, isHovering: isHovering, isEditing: true,
                pageTitle: "Title", urlString: Self.url, host: Self.host
            )
            #expect(state.text == Self.url)
            #expect(state.isEditable == true)
        }
    }

    @Test func hoveringWithoutEditingShowsReadOnlyURL() {
        let state = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: true, isEditing: false,
            pageTitle: "Title", urlString: Self.url, host: Self.host
        )
        #expect(state.text == Self.url)
        #expect(state.isEditable == false)
    }

    @Test func leavingHoverWithoutEditingRevertsToTitle() {
        let state = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: false,
            pageTitle: "Title", urlString: Self.url, host: Self.host
        )
        #expect(state.text == "Title")
    }

    @Test func editingShowsEditableURL() {
        let state = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: true,
            pageTitle: "Title", urlString: Self.url, host: Self.host
        )
        #expect(state.text == Self.url)
        #expect(state.isEditable == true)
    }

    @Test func blurringWithoutSubmittingRevertsToTitle() {
        let state = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: false,
            pageTitle: "Title", urlString: Self.url, host: Self.host
        )
        #expect(state.text == "Title")
        #expect(state.isEditable == false)
    }

    @Test func defaultDisplayFallsBackFromTitleToHostToEmptyString() {
        let withTitle = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: false,
            pageTitle: "Title", urlString: Self.url, host: Self.host
        )
        #expect(withTitle.text == "Title")

        let withoutTitle = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: false,
            pageTitle: nil, urlString: Self.url, host: Self.host
        )
        #expect(withoutTitle.text == Self.host)

        let withEmptyTitle = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: false,
            pageTitle: "", urlString: Self.url, host: Self.host
        )
        #expect(withEmptyTitle.text == Self.host)

        let withNeither = AddressFieldPresenter.displayState(
            isLoading: false, isHovering: false, isEditing: false,
            pageTitle: nil, urlString: Self.url, host: nil
        )
        #expect(withNeither.text == "")
    }

    @Test func aLiveEditingSessionOutranksEveryPageDrivenUpdate() {
        #expect(AddressFieldPresenter.acceptsPageDrivenUpdates(hasActiveEditingSession: true) == false)
    }

    @Test func pageDrivenUpdatesResumeOnceTheEditingSessionIsOver() {
        #expect(AddressFieldPresenter.acceptsPageDrivenUpdates(hasActiveEditingSession: false) == true)
    }

    @Test(arguments: [false, true])
    func embeddedRefreshIconIsHiddenUntilTheFirstRealNavigation(isEditing: Bool) {
        #expect(AddressFieldPresenter.showsEmbeddedRefreshIcon(
            hasNavigatedAtLeastOnce: false, isEditing: isEditing) == false)
    }

    @Test func embeddedRefreshIconIsShownOnceANavigationHasHappened() {
        #expect(AddressFieldPresenter.showsEmbeddedRefreshIcon(
            hasNavigatedAtLeastOnce: true, isEditing: false) == true)
    }

    @Test func embeddedRefreshIconIsHiddenWhileTheFieldIsBeingEdited() {
        #expect(AddressFieldPresenter.showsEmbeddedRefreshIcon(
            hasNavigatedAtLeastOnce: true, isEditing: true) == false)
    }

    @Test func windowTitleFallsBackFromTitleToHostToMochi() {
        #expect(AddressFieldPresenter.windowTitle(pageTitle: "Title", host: Self.host) == "Title")
        #expect(AddressFieldPresenter.windowTitle(pageTitle: nil, host: Self.host) == Self.host)
        #expect(AddressFieldPresenter.windowTitle(pageTitle: "", host: Self.host) == Self.host)
        #expect(AddressFieldPresenter.windowTitle(pageTitle: nil, host: nil) == "Mochi")
        #expect(AddressFieldPresenter.windowTitle(pageTitle: "", host: "") == "Mochi")
    }
}
