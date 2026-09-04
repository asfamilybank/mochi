import Foundation
import Testing

@testable import MochiCore

@Suite struct AddressFieldPresenterTests {
    private static let url = "https://example.com/page"
    private static let host = "example.com"

    @Test func loadingAlwaysShowsURLRegardlessOfHoverOrEditing() {
        for (isHovering, isEditing) in [(false, false), (true, false), (false, true), (true, true)] {
            let state = AddressFieldPresenter.displayState(
                isLoading: true, isHovering: isHovering, isEditing: isEditing,
                pageTitle: "Title", urlString: Self.url, host: Self.host
            )
            #expect(state.text == Self.url)
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

    @Test func embeddedRefreshIconIsHiddenUntilTheFirstRealNavigation() {
        #expect(AddressFieldPresenter.showsEmbeddedRefreshIcon(hasNavigatedAtLeastOnce: false) == false)
    }

    @Test func embeddedRefreshIconIsShownOnceANavigationHasHappened() {
        #expect(AddressFieldPresenter.showsEmbeddedRefreshIcon(hasNavigatedAtLeastOnce: true) == true)
    }

    @Test func windowTitleFallsBackFromTitleToHostToMochi() {
        #expect(AddressFieldPresenter.windowTitle(pageTitle: "Title", host: Self.host) == "Title")
        #expect(AddressFieldPresenter.windowTitle(pageTitle: nil, host: Self.host) == Self.host)
        #expect(AddressFieldPresenter.windowTitle(pageTitle: "", host: Self.host) == Self.host)
        #expect(AddressFieldPresenter.windowTitle(pageTitle: nil, host: nil) == "Mochi")
        #expect(AddressFieldPresenter.windowTitle(pageTitle: "", host: "") == "Mochi")
    }
}
