import Foundation
import Testing

@testable import MochiCore

@Suite struct AddressBarLayoutTests {
    private static func placement(
        capsuleWidth: Double = 300, contentWidth: Double, isEditing: Bool, pinsIcon: Bool = false,
        trailingReserved: Double = 28
    ) -> AddressBarLayout.Placement {
        AddressBarLayout.placement(
            capsuleWidth: capsuleWidth, contentWidth: contentWidth, isEditing: isEditing, pinsIcon: pinsIcon,
            leadingPadding: 7, iconSize: 16, iconTextGap: 4, trailingReserved: trailingReserved)
    }

    /// Editing parks the icon at the leading edge and gives the field every point up to the
    /// trailing reservation, whatever the text happens to be.
    @Test(arguments: [0.0, 40, 1_000])
    func editingPinsTheIconLeadingAndFillsTheMiddle(contentWidth: Double) {
        let p = Self.placement(contentWidth: contentWidth, isEditing: true)
        #expect(p == AddressBarLayout.Placement(iconMinX: 7, fieldMinX: 27, fieldWidth: 300 - 27 - 28))
    }

    /// Short text: the icon + text group sits on the capsule's center, not the field's.
    @Test func displayCentersIconAndTextTogetherOnTheCapsule() {
        let p = Self.placement(contentWidth: 60, isEditing: false)
        // group = 16 + 4 + 60 = 80, centered in 300 → starts at 110.
        #expect(p == AddressBarLayout.Placement(iconMinX: 110, fieldMinX: 130, fieldWidth: 60))
    }

    /// Text wider than the middle: the field is capped and lands exactly on the editing layout,
    /// so clicking a long title doesn't shift anything sideways.
    @Test func displayOfOverlongTextMatchesTheEditingLayout() {
        let display = Self.placement(contentWidth: 1_000, isEditing: false)
        let editing = Self.placement(contentWidth: 1_000, isEditing: true)
        #expect(display == editing)
    }

    /// Centering would overlap the trailing reservation, so the group is pushed back inside it.
    @Test func displayGroupNeverRunsIntoTheTrailingReservation() {
        let p = Self.placement(contentWidth: 200, isEditing: false, trailingReserved: 60)
        #expect(p.fieldMinX + p.fieldWidth <= 300 - 60)
        #expect(p.iconMinX >= 7)
    }

    /// The Empty Page hides refresh, so only the edge padding is reserved and the centered group
    /// is symmetric.
    @Test func displayWithoutRefreshIsCenteredSymmetrically() {
        let p = Self.placement(contentWidth: 80, isEditing: false, trailingReserved: 7)
        let groupMaxX = p.fieldMinX + p.fieldWidth
        #expect(p.iconMinX == 300 - groupMaxX)
    }

    /// On a page the site icon holds the leading edge and only the title is centered.
    @Test func pinnedIconStaysLeadingWhileTheTextCentersOnTheCapsule() {
        let p = Self.placement(contentWidth: 60, isEditing: false, pinsIcon: true)
        #expect(p == AddressBarLayout.Placement(iconMinX: 7, fieldMinX: 120, fieldWidth: 60))
    }

    /// A title that fills the middle can't be centered without overlapping the icon, so it starts
    /// right after it — exactly the editing layout.
    @Test func pinnedIconPushesAWideTitleClearOfTheIcon() {
        let display = Self.placement(contentWidth: 1_000, isEditing: false, pinsIcon: true)
        let editing = Self.placement(contentWidth: 1_000, isEditing: true, pinsIcon: true)
        #expect(display == editing)
    }

    /// Clicking only slides the text: the icon is already where editing wants it.
    @Test func pinnedIconDoesNotMoveWhenEditingStarts() {
        let display = Self.placement(contentWidth: 60, isEditing: false, pinsIcon: true)
        let editing = Self.placement(contentWidth: 60, isEditing: true, pinsIcon: true)
        #expect(display.iconMinX == editing.iconMinX)
    }
}
